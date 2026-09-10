[CmdletBinding()]
param(
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\identity-production-v4-brazil.json'),
    [Parameter(Mandatory)][string]$SelectionPath,
    [string]$RunDirectory = (Join-Path $PSScriptRoot '..\runs\identity-production-v4-brazil'),
    [ValidateRange(60, 7200)][int]$TimeoutSec = 1800,
    [switch]$AllowPartial,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing.Common
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$config = Get-Content -LiteralPath (Resolve-Path -LiteralPath $ConfigPath).Path -Raw | ConvertFrom-Json
$selection = Get-Content -LiteralPath (Resolve-Path -LiteralPath $SelectionPath).Path -Raw | ConvertFrom-Json
$runRoot = (Resolve-Path -LiteralPath $RunDirectory).Path
$finalRoot = Join-Path $runRoot 'final-review'
$maskRoot = Join-Path $finalRoot 'masks'
$intermediateRoot = Join-Path $finalRoot 'intermediates'
$cropRoot = Join-Path $finalRoot 'crops'
New-Item -ItemType Directory -Path $finalRoot, $maskRoot, $intermediateRoot, $cropRoot -Force | Out-Null
$baseUri = $ApiBaseUri.TrimEnd('/')
$referencePath = (Resolve-Path -LiteralPath (Join-Path $repoRoot ([string]$config.subject.reference_image))).Path
$referenceHash = (Get-FileHash -LiteralPath $referencePath -Algorithm SHA256).Hash
if ($referenceHash -ine [string]$config.subject.reference_sha256) { throw 'Identity reference hash mismatch.' }
$referenceBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($referencePath))
if (-not $AllowPartial -and @($selection.selections).Count -ne 10) { throw 'Final delivery requires exactly ten selections. Use -AllowPartial only for a pipeline test.' }
if (@($selection.selections.shot | Sort-Object -Unique).Count -ne @($selection.selections).Count) { throw 'Every selected shot must be unique.' }

function Wait-SDNextIdle {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $progress = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/progress?skip_current_image=true" -TimeoutSec 15
        if ([int]$progress.state.sampling_steps -eq 0 -and [double]$progress.progress -eq 0) { return }
        Start-Sleep -Seconds 10
    }
    throw "SD.Next remained busy longer than $TimeoutSec seconds."
}

function Get-Base64([string]$Path) { return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) }
function Save-Base64([string]$Encoded, [string]$Path) {
    $clean = $Encoded -replace '^data:image/[^;]+;base64,', ''
    [IO.File]::WriteAllBytes($Path, [Convert]::FromBase64String($clean))
}

function New-DetectionMask {
    param([Parameter(Mandatory)][string]$ImagePath, [Parameter(Mandatory)][string]$Detector, [Parameter(Mandatory)][string]$OutputPath)
    $payload = @{ image = Get-Base64 $ImagePath; model = $Detector }
    Wait-SDNextIdle
    $detected = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/detect" -Method Post -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 8) -TimeoutSec $TimeoutSec
    if (-not $detected.boxes -or $detected.boxes.Count -lt 1) { throw "$Detector found no region in $ImagePath." }
    $source = [Drawing.Image]::FromFile($ImagePath)
    $mask = [Drawing.Bitmap]::new($source.Width, $source.Height)
    $graphics = [Drawing.Graphics]::FromImage($mask)
    try {
        $graphics.Clear([Drawing.Color]::Black)
        foreach ($box in $detected.boxes) {
            $x1=[int]$box[0]; $y1=[int]$box[1]; $x2=[int]$box[2]; $y2=[int]$box[3]
            $pad=[int]([Math]::Max($x2-$x1,$y2-$y1)*0.18)
            $left=[Math]::Max(0,$x1-$pad); $top=[Math]::Max(0,$y1-$pad)
            $right=[Math]::Min($source.Width,$x2+$pad); $bottom=[Math]::Min($source.Height,$y2+$pad)
            $graphics.FillRectangle([Drawing.Brushes]::White,$left,$top,$right-$left,$bottom-$top)
        }
        $mask.Save($OutputPath,[Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $graphics.Dispose(); $mask.Dispose(); $source.Dispose() }
}

function Invoke-LocalInpaint {
    param([string]$ImagePath,[string]$MaskPath,[string]$Prompt,[long]$Seed,[string]$OutputPath,[bool]$UseIdentity)
    $source = [Drawing.Image]::FromFile($ImagePath)
    try { $width=$source.Width; $height=$source.Height } finally { $source.Dispose() }
    $payload = [ordered]@{
        init_images = @(Get-Base64 $ImagePath); mask = Get-Base64 $MaskPath; prompt = $Prompt
        negative_prompt = [string]$config.negative_prompt; seed = $Seed; steps = [int]$config.finalization.detail_steps
        width = $width; height = $height; sampler_name = [string]$config.model.sampler; schedulers_sigma = [string]$config.model.scheduler
        cfg_scale = 5.5; guidance_scale = 5.5; denoising_strength = [double]$config.finalization.detail_strength
        mask_blur = [int]$config.finalization.detail_blur; inpainting_fill = 1; inpaint_full_res = $true
        inpaint_full_res_padding = [int]$config.finalization.detail_padding; inpainting_mask_invert = 0
        batch_size = 1; n_iter = 1; vae_type = [string]$config.model.vae; save_images = $false; send_images = $true
    }
    if ($UseIdentity) {
        $payload.ip_adapter = @([ordered]@{ adapter=[string]$config.identity.ip_adapter; images=@($referenceBase64); masks=@(); scale=[double]$config.identity.ip_scale; start=0.0; end=0.75; crop=$true })
    }
    Wait-SDNextIdle
    $response = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/img2img" -Method Post -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 20) -TimeoutSec $TimeoutSec
    if (-not $response.images -or $response.images.Count -lt 1) { throw 'Localized inpainting returned no image.' }
    Save-Base64 ([string]$response.images[0]) $OutputPath
}

function Invoke-Upscale {
    param([string]$ImagePath,[string]$Upscaler,[string]$OutputPath)
    $payload = @{ image=Get-Base64 $ImagePath; resize_mode=0; show_extras_results=$true; upscaling_resize=2; upscaling_crop=$false; upscaler_1=$Upscaler; upscaler_2='None'; extras_upscaler_2_visibility=0 }
    Wait-SDNextIdle
    $response = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/extra-single-image" -Method Post -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 10) -TimeoutSec $TimeoutSec
    if (-not $response.image) { throw "$Upscaler returned no image." }
    Save-Base64 ([string]$response.image) $OutputPath
}

function Export-DetectionCrop {
    param([string]$ImagePath,[string]$Detector,[string]$OutputPath)
    $payload = @{ image=Get-Base64 $ImagePath; model=$Detector }
    Wait-SDNextIdle
    $detected = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/detect" -Method Post -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 8) -TimeoutSec $TimeoutSec
    if (-not $detected.boxes -or $detected.boxes.Count -lt 1) { return '' }
    $box=$detected.boxes[0]
    $source=[Drawing.Bitmap]::new($ImagePath)
    try {
        $x1=[int]$box[0];$y1=[int]$box[1];$x2=[int]$box[2];$y2=[int]$box[3]
        $pad=[int]([Math]::Max($x2-$x1,$y2-$y1)*0.25)
        $left=[Math]::Max(0,$x1-$pad);$top=[Math]::Max(0,$y1-$pad)
        $right=[Math]::Min($source.Width,$x2+$pad);$bottom=[Math]::Min($source.Height,$y2+$pad)
        $rect=[Drawing.Rectangle]::new($left,$top,$right-$left,$bottom-$top)
        $crop=$source.Clone($rect,$source.PixelFormat)
        try { $crop.Save($OutputPath,[Drawing.Imaging.ImageFormat]::Png) } finally { $crop.Dispose() }
    }
    finally { $source.Dispose() }
    return $OutputPath
}

$records = @()
foreach ($item in $selection.selections) {
    $sourcePath = [IO.Path]::GetFullPath((Join-Path $runRoot ([string]$item.source)))
    if (-not $sourcePath.StartsWith($runRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "Selected source escapes the V4 run directory: $($item.source)" }
    if (-not (Test-Path -LiteralPath $sourcePath)) { throw "Selected source does not exist: $sourcePath" }
    $working = $sourcePath
    $seedRecord = Import-Csv (Join-Path $runRoot 'manifest.csv') | Where-Object { $_.file -eq $item.source } | Select-Object -First 1
    $seed = if ($seedRecord) { [long]$seedRecord.seed } else { -1 }
    foreach ($kind in @($item.corrections)) {
        $detector = switch ($kind) { 'face' { [string]$config.finalization.face_detector } 'eyes' { [string]$config.finalization.eye_detector } 'hands' { [string]$config.finalization.hand_detector } default { throw "Unknown correction '$kind'. Use face, eyes, or hands." } }
        $maskPath = Join-Path $maskRoot "$($item.shot)-$kind-mask.png"
        $correctedPath = Join-Path $intermediateRoot "$($item.shot)-$kind-corrected.png"
        New-DetectionMask -ImagePath $working -Detector $detector -OutputPath $maskPath
        $prompt = if ($kind -eq 'hands') { 'natural anatomically correct adult hands, five separate fingers, realistic skin texture, ordinary photograph' } else { "$($config.identity.prompt), natural aligned brown eyes with coherent catchlights, individual natural teeth only if visible, real skin pores, ordinary unretouched photograph" }
        Invoke-LocalInpaint -ImagePath $working -MaskPath $maskPath -Prompt $prompt -Seed $seed -OutputPath $correctedPath -UseIdentity ($kind -ne 'hands')
        $working = $correctedPath
    }
    foreach ($upscaler in $config.finalization.upscalers) {
        $slug = if ($upscaler -eq 'Resize Lanczos') { 'lanczos' } else { 'realesrgan' }
        $outputPath = Join-Path $finalRoot "$($item.shot)-$slug-2x.png"
        if ((Test-Path -LiteralPath $outputPath) -and -not $Force) { continue }
        Invoke-Upscale -ImagePath $working -Upscaler ([string]$upscaler) -OutputPath $outputPath
        $faceCrop = Export-DetectionCrop -ImagePath $outputPath -Detector ([string]$config.finalization.face_detector) -OutputPath (Join-Path $cropRoot "$($item.shot)-$slug-face.png")
        $handCrop = Export-DetectionCrop -ImagePath $outputPath -Detector ([string]$config.finalization.hand_detector) -OutputPath (Join-Path $cropRoot "$($item.shot)-$slug-hand.png")
        $records += [pscustomobject]@{ shot=$item.shot; source=$item.source; corrected_source=[IO.Path]::GetRelativePath($runRoot,$working); upscaler=$upscaler; file=[IO.Path]::GetRelativePath($runRoot,$outputPath); face_crop=if($faceCrop){[IO.Path]::GetRelativePath($runRoot,$faceCrop)}else{''}; hand_crop=if($handCrop){[IO.Path]::GetRelativePath($runRoot,$handCrop)}else{''}; sha256=(Get-FileHash $outputPath -Algorithm SHA256).Hash; status='review-required' }
    }
}
$records | Export-Csv -LiteralPath (Join-Path $finalRoot 'finalization.csv') -NoTypeInformation -Encoding utf8
$cards = foreach($r in $records){
    $details=@()
    if($r.face_crop){$details += "<img class='crop' src='../$($r.face_crop -replace '\\','/')' alt='face crop'>"}
    if($r.hand_crop){$details += "<img class='crop' src='../$($r.hand_crop -replace '\\','/')' alt='hand crop'>"}
    "<figure><a href='../$($r.file -replace '\\','/')'><img src='../$($r.file -replace '\\','/')'></a><div class='crops'>$($details -join '')</div><figcaption>$($r.shot) — $($r.upscaler)<br>$($r.file)</figcaption></figure>"
}
@"
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>V4 final review</title><style>body{font-family:Arial;background:#111;color:#eee;margin:24px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:18px}figure{background:#222;padding:10px;margin:0}figure>a>img{width:100%;height:520px;object-fit:contain;background:#080808}.crops{display:flex;gap:8px;margin-top:8px}.crop{width:48%;height:160px;object-fit:contain;background:#080808}figcaption{margin-top:8px;font-size:13px}</style></head><body><h1>V4 final review</h1><p>Compare both 2x methods and the detected face/hand crops at full resolution. No image is automatically approved.</p><div class="grid">$($cards -join "`n")</div></body></html>
"@ | Set-Content -LiteralPath (Join-Path $finalRoot 'final-review.html') -Encoding utf8
Write-Host "Final review: $(Join-Path $finalRoot 'final-review.html')"
