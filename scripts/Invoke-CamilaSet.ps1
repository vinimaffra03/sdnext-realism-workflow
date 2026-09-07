[CmdletBinding()]
param(
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\camila-claude-v1.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\runs\camila-claude-v1'),
    [string]$BaselineImage = (Join-Path $PSScriptRoot '..\samples\baseline-n9.png'),
    [int]$Count = 20,
    [int]$SeedStep = 1000
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SDNext.Common.ps1')

$config = Read-WorkflowConfig -Path $ConfigPath
$baseUri = $ApiBaseUri.TrimEnd('/')
$apiUri = "$baseUri/sdapi/v1/txt2img"
$models = @(Get-SDNextModels -ApiBaseUri $baseUri)
$checkpoint = Resolve-SDNextCheckpoint -Models $models -Config $config
$results = [System.Collections.Generic.List[object]]::new()
$baseSeed = [long]$config.seed

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

for ($index = 1; $index -le $Count; $index++) {
    $seed = $baseSeed + (($index - 1) * $SeedStep)
    $fileName = '{0:D2}_camila_seed-{1}.png' -f $index, $seed
    $filePath = Join-Path $OutputDirectory $fileName
    $started = Get-Date

    if (Test-Path -LiteralPath $filePath) {
        Write-Output "[$index/$Count] Existing: $fileName"
        $status = 'existing'
        $elapsed = 0
    }
    else {
        Write-Output "[$index/$Count] Generating seed $seed..."
        $payload = [ordered]@{
            sd_model_checkpoint = [string]$checkpoint.title
            prompt = [string]$config.prompt
            negative_prompt = [string]$config.negative_prompt
            seed = [long]$seed
            batch_size = 1
            n_iter = 1
            steps = [int]$config.steps
            width = [int]$config.width
            height = [int]$config.height
            sampler_name = [string]$config.sampler_name
            schedulers_sigma = [string]$config.schedulers_sigma
            cfg_scale = [double]$config.cfg_scale
            guidance_scale = [double]$config.guidance_scale
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
            Write-Warning "[$index/$Count] Failed: $($_.Exception.Message)"
            $status = 'failed'
        }
        $elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    }

    $results.Add([pscustomobject]@{
        index = $index
        file = $fileName
        variant = [string]$config.variant
        sampler = [string]$config.sampler_name
        sigma = [string]$config.schedulers_sigma
        cfg = [double]$config.cfg_scale
        steps = [int]$config.steps
        seed = [long]$seed
        width = [int]$config.width
        height = [int]$config.height
        elapsed_seconds = $elapsed
        status = $status
    })
}

$manifestPath = Join-Path $OutputDirectory 'manifest.csv'
$results | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8

Add-Type -AssemblyName System.Drawing
$tileSize = 256
$labelHeight = 46
$columns = 4
$rows = [int][math]::Ceiling($Count / $columns)
$sheet = [Drawing.Bitmap]::new($tileSize * $columns, ($tileSize + $labelHeight) * $rows)
$graphics = [Drawing.Graphics]::FromImage($sheet)
$graphics.Clear([Drawing.Color]::FromArgb(24, 24, 24))
$graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$font = [Drawing.Font]::new('Arial', 12, [Drawing.FontStyle]::Bold)
$brush = [Drawing.SolidBrush]::new([Drawing.Color]::White)
$format = [Drawing.StringFormat]::new()
$format.Alignment = [Drawing.StringAlignment]::Center
$format.LineAlignment = [Drawing.StringAlignment]::Center
$contactSheetPath = Join-Path $OutputDirectory 'contact-sheet.png'

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
        $label = '#{0:D2}  seed {1}' -f [int]$item.index, [long]$item.seed
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

$headToHeadPath = $null
$firstImage = Join-Path $OutputDirectory ('{0:D2}_camila_seed-{1}.png' -f 1, $baseSeed)
if ((Test-Path -LiteralPath $BaselineImage) -and (Test-Path -LiteralPath $firstImage)) {
    $panel = 512
    $captionHeight = 54
    $headToHead = [Drawing.Bitmap]::new($panel * 2, $panel + $captionHeight)
    $headToHeadGraphics = [Drawing.Graphics]::FromImage($headToHead)
    $headToHeadGraphics.Clear([Drawing.Color]::FromArgb(24, 24, 24))
    $headToHeadGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $headToHeadFont = [Drawing.Font]::new('Arial', 15, [Drawing.FontStyle]::Bold)
    $headToHeadBrush = [Drawing.SolidBrush]::new([Drawing.Color]::White)
    $headToHeadFormat = [Drawing.StringFormat]::new()
    $headToHeadFormat.Alignment = [Drawing.StringAlignment]::Center
    $headToHeadFormat.LineAlignment = [Drawing.StringAlignment]::Center

    try {
        $pairs = @(
            @{ Path = $BaselineImage; Label = 'GPT baseline N9 — seed 231984751'; X = 0 },
            @{ Path = $firstImage; Label = 'Claude Camila prompt — seed 231984751'; X = $panel }
        )
        foreach ($pair in $pairs) {
            $image = [Drawing.Image]::FromFile($pair.Path)
            try {
                $headToHeadGraphics.DrawImage($image, [int]$pair.X, 0, $panel, $panel)
            }
            finally {
                $image.Dispose()
            }
            $rect = [Drawing.RectangleF]::new([single]$pair.X, $panel, $panel, $captionHeight)
            $headToHeadGraphics.DrawString($pair.Label, $headToHeadFont, $headToHeadBrush, $rect, $headToHeadFormat)
        }
        $headToHeadPath = Join-Path $OutputDirectory 'head-to-head.png'
        $headToHead.Save($headToHeadPath, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $headToHeadFormat.Dispose()
        $headToHeadBrush.Dispose()
        $headToHeadFont.Dispose()
        $headToHeadGraphics.Dispose()
        $headToHead.Dispose()
    }
}

$generatedCount = @($results | Where-Object { $_.status -eq 'ok' }).Count
$failedCount = @($results | Where-Object { $_.status -eq 'failed' }).Count
$totalSeconds = [math]::Round((($results | Measure-Object -Property elapsed_seconds -Sum).Sum), 1)

Write-Output ''
Write-Output "Generated: $generatedCount   Failed: $failedCount   Total time: $totalSeconds seconds"
Write-Output "Manifest: $manifestPath"
Write-Output "Contact sheet: $contactSheetPath"
if ($headToHeadPath) {
    Write-Output "Head-to-head comparison: $headToHeadPath"
}
