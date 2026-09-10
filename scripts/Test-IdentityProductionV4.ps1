[CmdletBinding()]
param(
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\identity-production-v4-brazil.json')
)

$ErrorActionPreference = 'Stop'
$repoRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$config=Get-Content -LiteralPath (Resolve-Path $ConfigPath) -Raw | ConvertFrom-Json
if($config.shots.Count -ne 10){throw "Expected 10 shots; found $($config.shots.Count)."}
if(($config.shots.id | Sort-Object -Unique).Count -ne 10){throw 'Shot ids must be unique.'}
foreach($shot in $config.shots){
    if($shot.width -ne 512 -or $shot.height -notin @(512,768)){throw "Invalid dimensions for $($shot.id)."}
}
$reference=(Resolve-Path (Join-Path $repoRoot $config.subject.reference_image)).Path
$hash=(Get-FileHash $reference -Algorithm SHA256).Hash
if($hash -ine $config.subject.reference_sha256){throw 'Reference hash mismatch.'}
$base=$ApiBaseUri.TrimEnd('/')
$options=Invoke-RestMethod "$base/sdapi/v1/options" -TimeoutSec 30
if([string]$options.sd_model_checkpoint -notmatch '22c7896047'){throw "Wrong checkpoint: $($options.sd_model_checkpoint)"}
$adapters=Invoke-RestMethod "$base/sdapi/v1/ip-adapters" -TimeoutSec 30
if('Plus Face' -notin $adapters){throw 'Plus Face IP-Adapter is unavailable.'}
$detailers=Invoke-RestMethod "$base/sdapi/v1/detailers" -TimeoutSec 30
foreach($required in @($config.finalization.face_detector,$config.finalization.eye_detector,$config.finalization.hand_detector)){
    if($required -notin $detailers.name){throw "Detailer unavailable: $required"}
}
$upscalers=Invoke-RestMethod "$base/sdapi/v1/upscalers" -TimeoutSec 30
foreach($required in $config.finalization.upscalers){if($required -notin $upscalers.name){throw "Upscaler unavailable: $required"}}
$scripts=Invoke-RestMethod "$base/sdapi/v1/scripts" -TimeoutSec 30
if('face: multiple id transfers' -notin @($scripts.txt2img)){throw 'FaceID script is unavailable.'}
& (Join-Path $PSScriptRoot 'Invoke-IdentityProductionV4.ps1') -ApiBaseUri $ApiBaseUri -ConfigPath $ConfigPath -Mode Candidates -ValidateOnly | Out-Null
Write-Host 'V4 preflight passed: reference, 10 shots, checkpoint, IP-Adapter, FaceID, detailers, upscalers, and 100-job ceiling.'
