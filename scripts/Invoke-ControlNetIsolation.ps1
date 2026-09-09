[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RequestPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$ApiBaseUri = 'http://127.0.0.1:7860',

    [ValidateRange(1, 150)]
    [int]$Steps = 8,

    [switch]$KeepIPAdapter,

    [ValidateRange(0.0, 2.0)]
    [double]$IPAdapterScale = 0.45,

    [string]$IPAdapterImagePath,

    [string]$FaceSwapImagePath,

    [string]$AppendNegativePrompt,

    [ValidateRange(0.0, 1.0)]
    [Nullable[double]]$ControlGuidanceEnd,

    [ValidateRange(30, 3600)]
    [int]$TimeoutSec = 1800
)

$ErrorActionPreference = 'Stop'

$requestFile = (Resolve-Path -LiteralPath $RequestPath).Path
$request = Get-Content -LiteralPath $requestFile -Raw | ConvertFrom-Json

if (-not $request.control -or $request.control.Count -lt 1) {
    throw 'The source request does not contain a ControlNet unit.'
}

if ($null -ne $ControlGuidanceEnd) {
    $request.control[0].end = $ControlGuidanceEnd
}

# Keep the same seed, prompt, pose map, ControlNet weight, and guidance values.
# Removing IP-Adapter isolates whether identity conditioning is competing with pose.
if ($KeepIPAdapter -and $FaceSwapImagePath) {
    throw 'Use either IP-Adapter or FaceSwap for an isolation run, not both.'
}

if ($KeepIPAdapter) {
    if (-not $request.ip_adapter -or $request.ip_adapter.Count -lt 1) {
        throw 'The source request does not contain an IP-Adapter configuration.'
    }
    $request.ip_adapter[0].scale = $IPAdapterScale
    if ($IPAdapterImagePath) {
        $identityImage = (Resolve-Path -LiteralPath $IPAdapterImagePath).Path
        $request.ip_adapter[0].images = @([Convert]::ToBase64String([IO.File]::ReadAllBytes($identityImage)))
        $request.ip_adapter[0].crop = $false
    }
}
else {
    $request.PSObject.Properties.Remove('ip_adapter')
}


if ($FaceSwapImagePath) {
    $faceImage = (Resolve-Path -LiteralPath $FaceSwapImagePath).Path
    $request | Add-Member -NotePropertyName face -NotePropertyValue ([pscustomobject]@{
        mode = 'FaceSwap'
        source_images = @([Convert]::ToBase64String([IO.File]::ReadAllBytes($faceImage)))
        fs_cache = $true
    }) -Force
}
$request.steps = $Steps
$request.send_images = $true
$request.save_images = $false

if ($AppendNegativePrompt) {
    $request.negative_prompt = ([string]$request.negative_prompt).Trim().TrimEnd(',') + ', ' + $AppendNegativePrompt.Trim().TrimStart(',').Trim()
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutput
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

$requestSnapshot = [IO.Path]::ChangeExtension($resolvedOutput, '.request.json')
$request | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $requestSnapshot -Encoding utf8NoBOM

$uri = $ApiBaseUri.TrimEnd('/') + '/sdapi/v1/control'
$referenceMode = if ($KeepIPAdapter -and $IPAdapterImagePath) { ', explicit face crop' } else { '' }
$mode = if ($KeepIPAdapter) {
    "ControlNet + IP-Adapter scale $IPAdapterScale$referenceMode"
}
elseif ($FaceSwapImagePath) {
    'ControlNet + post-generation FaceSwap'
}
else {
    'ControlNet only'
}
Write-Host "Running diagnostic: $mode, $Steps steps"
$response = Invoke-RestMethod -Method Post -Uri $uri -ContentType 'application/json' -Body ($request | ConvertTo-Json -Depth 30 -Compress) -TimeoutSec $TimeoutSec

if (-not $response.images -or $response.images.Count -lt 1) {
    throw "The SD.Next response did not contain an image. Info: $($response.info)"
}

$encoded = [string]$response.images[0]
$encoded = $encoded -replace '^data:image/[^;]+;base64,', ''
$bytes = [Convert]::FromBase64String($encoded)

Add-Type -AssemblyName System.Drawing
$memory = [IO.MemoryStream]::new($bytes, $false)
try {
    $image = [Drawing.Image]::FromStream($memory)
    try {
        $image.Save($resolvedOutput, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $image.Dispose()
    }
}
finally {
    $memory.Dispose()
}

$infoPath = [IO.Path]::ChangeExtension($resolvedOutput, '.response-info.txt')
[IO.File]::WriteAllText($infoPath, [string]$response.info, [Text.UTF8Encoding]::new($false))

$saved = Get-Item -LiteralPath $resolvedOutput
if ($saved.Length -lt 1024) {
    throw "The saved image is unexpectedly small: $($saved.Length) bytes."
}

Write-Host "Saved: $resolvedOutput"
Write-Host "Request: $requestSnapshot"
Write-Host "Response info: $infoPath"
