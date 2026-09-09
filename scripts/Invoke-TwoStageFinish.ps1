[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$IdentityPath,
    [Parameter(Mandatory = $true)][string]$RequestPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$PackagePath = 'D:\AIMODEL\StabilityMatrix-win-x64\Data\Packages\SD.Next',
    [string]$AnalysisRoot = 'D:\AIMODEL\StabilityMatrix-win-x64\Data\Models\Diffusers\models--vladmandic--insightface-faceanalysis',
    [string]$SwapperModel = 'D:\AIMODEL\StabilityMatrix-win-x64\Data\Packages\SD.Next\models\huggingface\models--ezioruan--inswapper_128.onnx\snapshots\6ffdf0e83c5996cc425e77b59913fc48d79441be\inswapper_128.onnx',
    [switch]$SkipDetailer,
    [ValidateRange(60, 3600)][int]$TimeoutSec = 1800
)

$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $SourcePath).Path
$identity = (Resolve-Path -LiteralPath $IdentityPath).Path
$request = Get-Content -LiteralPath (Resolve-Path -LiteralPath $RequestPath).Path -Raw | ConvertFrom-Json
$output = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $output
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

function Get-ImageBase64([string]$Path) {
    return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
}

function Save-Base64Image([string]$Encoded, [string]$Path) {
    $clean = $Encoded -replace '^data:image/[^;]+;base64,', ''
    [IO.File]::WriteAllBytes($Path, [Convert]::FromBase64String($clean))
    if ((Get-Item -LiteralPath $Path).Length -lt 1024) {
        throw "Saved image is unexpectedly small: $Path"
    }
}

function Invoke-SDNext([string]$Endpoint, [object]$Payload) {
    $uri = $ApiBaseUri.TrimEnd('/') + $Endpoint
    return Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json' -Body ($Payload | ConvertTo-Json -Depth 20 -Compress) -TimeoutSec $TimeoutSec
}

$detailPath = [IO.Path]::ChangeExtension($output, '.detail.png')
$upscaledPath = [IO.Path]::ChangeExtension($output, '.upscaled-base.png')
$finishSource = $source

if (-not $SkipDetailer) {
    Write-Host 'Running conservative face detailer...'
    $detailPayload = [ordered]@{
        image = Get-ImageBase64 $source
        seed = [long]$request.seed
        detailer_models = @('face-yolo8n')
        detailer_prompt = [string]$request.prompt
        detailer_negative = [string]$request.negative_prompt
        detailer_steps = 10
        detailer_strength = 0.25
        detailer_resolution = 768
        detailer_sampler = [string]$request.sampler_name
        detailer_cfg_scale = [double]$request.cfg_scale
        detailer_classes = 'face'
        detailer_conf = 0.3
        detailer_max = 1
        detailer_blur = 8
        detailer_padding = 16
    }
    $detailResponse = Invoke-SDNext '/sdapi/v1/detail' $detailPayload
    if (-not $detailResponse.image) { throw 'The detailer returned no image.' }
    Save-Base64Image ([string]$detailResponse.image) $detailPath
    $finishSource = $detailPath
}

Write-Host 'Upscaling the approved composition 2x...'
$upscalePayload = [ordered]@{
    image = Get-ImageBase64 $finishSource
    resize_mode = 0
    show_extras_results = $true
    upscaling_resize = 2
    upscaling_crop = $false
    upscaler_1 = 'Spandrel 2x RealESRGAN Compact'
    upscaler_2 = 'None'
    extras_upscaler_2_visibility = 0
}
$upscaleResponse = Invoke-SDNext '/sdapi/v1/extra-single-image' $upscalePayload
if (-not $upscaleResponse.image) { throw 'The upscaler returned no image.' }
Save-Base64Image ([string]$upscaleResponse.image) $upscaledPath

Write-Host 'Applying identity after composition and upscale...'
$python = Join-Path $PackagePath 'venv\Scripts\python.exe'
$faceSwapScript = Join-Path $PSScriptRoot 'Invoke-OfflineFaceSwap.py'
& $python $faceSwapScript --source $identity --target $upscaledPath --output $output --analysis-root $AnalysisRoot --swapper-model $SwapperModel
if ($LASTEXITCODE -ne 0) { throw "Offline FaceSwap failed with exit code $LASTEXITCODE." }

Write-Host "Final image: $output"
Write-Host "Upscaled pre-swap intermediate: $upscaledPath"
if (-not $SkipDetailer) { Write-Host "Detailer intermediate: $detailPath" }
