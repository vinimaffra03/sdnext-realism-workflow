[CmdletBinding()]
param(
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\baseline-n9.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\runs\matrix')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SDNext.Common.ps1')

$config = Read-WorkflowConfig -Path $ConfigPath
$baseUri = $ApiBaseUri.TrimEnd('/')
$apiUri = "$baseUri/sdapi/v1/txt2img"
$models = @(Get-SDNextModels -ApiBaseUri $baseUri)
$checkpoint = Resolve-SDNextCheckpoint -Models $models -Config $config
$samplers = @('DPM++ 2M', 'DPM++ SDE', 'Euler a', 'UniPC')
$cfgValues = @(4.5, 5.0, 5.5, 6.0, 6.5)
$results = [System.Collections.Generic.List[object]]::new()
$culture = [Globalization.CultureInfo]::InvariantCulture
$index = 0

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

foreach ($samplerName in $samplers) {
    foreach ($cfgValue in $cfgValues) {
        $index++
        $samplerSlug = (($samplerName -replace '[^A-Za-z0-9]+', '-').Trim('-')).ToLowerInvariant()
        $cfgText = $cfgValue.ToString('0.0', $culture)
        $cfgSlug = $cfgText.Replace('.', 'p')
        $fileName = '{0:D2}_{1}_cfg-{2}_seed-{3}.png' -f $index, $samplerSlug, $cfgSlug, $config.seed
        $filePath = Join-Path $OutputDirectory $fileName
        $started = Get-Date

        if (Test-Path -LiteralPath $filePath) {
            Write-Output "[$index/20] Existing: $fileName"
            $status = 'existing'
            $elapsed = 0
        }
        else {
            Write-Output "[$index/20] Generating $samplerName, CFG $cfgText..."
            $payload = [ordered]@{
                sd_model_checkpoint = [string]$checkpoint.title
                prompt = [string]$config.prompt
                negative_prompt = [string]$config.negative_prompt
                seed = [long]$config.seed
                batch_size = 1
                n_iter = 1
                steps = [int]$config.steps
                width = [int]$config.width
                height = [int]$config.height
                sampler_name = $samplerName
                schedulers_sigma = [string]$config.schedulers_sigma
                cfg_scale = [double]$cfgValue
                guidance_scale = [double]$cfgValue
                vae_type = [string]$config.vae_type
                detailer_enabled = $false
                enable_hr = $false
                save_images = $false
                send_images = $true
                do_not_save_samples = $true
            }

            try {
                $response = Invoke-RestMethod -Uri $apiUri -Method Post -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 6) -TimeoutSec 900
                Save-SDNextImageResponse -Response $response -OutputPath $filePath
                $status = 'ok'
            }
            catch {
                Write-Warning "[$index/20] Failed: $($_.Exception.Message)"
                $status = 'failed'
            }
            $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
        }

        $results.Add([pscustomobject]@{
            index = $index
            file = $fileName
            sampler = $samplerName
            sigma = [string]$config.schedulers_sigma
            cfg = $cfgText
            steps = [int]$config.steps
            seed = [long]$config.seed
            width = [int]$config.width
            height = [int]$config.height
            elapsed_seconds = $elapsed
            status = $status
        })
    }
}

$manifestPath = Join-Path $OutputDirectory 'manifest.csv'
$results | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8

Add-Type -AssemblyName System.Drawing
$tileSize = 256
$labelHeight = 46
$columns = 4
$rows = 5
$sheet = [Drawing.Bitmap]::new($tileSize * $columns, ($tileSize + $labelHeight) * $rows)
$graphics = [Drawing.Graphics]::FromImage($sheet)
$graphics.Clear([Drawing.Color]::FromArgb(24, 24, 24))
$graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = [Drawing.Font]::new('Arial', 13, [Drawing.FontStyle]::Bold)
$brush = [Drawing.SolidBrush]::new([Drawing.Color]::White)
$format = [Drawing.StringFormat]::new()
$format.Alignment = [Drawing.StringAlignment]::Center
$format.LineAlignment = [Drawing.StringAlignment]::Center
$contactSheetPath = Join-Path $OutputDirectory '20-image-comparison.png'

try {
    foreach ($item in $results | Where-Object { $_.status -ne 'failed' }) {
        $position = [int]$item.index - 1
        $column = $position % $columns
        $row = [math]::Floor($position / $columns)
        $x = $column * $tileSize
        $y = $row * ($tileSize + $labelHeight)
        $sourceImage = [Drawing.Image]::FromFile((Join-Path $OutputDirectory $item.file))
        try {
            $graphics.DrawImage($sourceImage, $x, $y, $tileSize, $tileSize)
        }
        finally {
            $sourceImage.Dispose()
        }
        $labelRect = [Drawing.RectangleF]::new($x, $y + $tileSize, $tileSize, $labelHeight)
        $label = '#{0:D2}  {1}  CFG {2}' -f [int]$item.index, [string]$item.sampler, [string]$item.cfg
        $graphics.DrawString($label, $font, $brush, $labelRect, $format)
    }
    $sheet.Save($contactSheetPath, [Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $format.Dispose()
    $brush.Dispose()
    $font.Dispose()
    $graphics.Dispose()
    $sheet.Dispose()
}

Write-Output "Manifest: $manifestPath"
Write-Output "Comparison sheet: $contactSheetPath"

