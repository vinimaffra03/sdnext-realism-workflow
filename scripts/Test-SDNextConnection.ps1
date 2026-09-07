[CmdletBinding()]
param(
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\baseline-n9.json')
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SDNext.Common.ps1')

$config = Read-WorkflowConfig -Path $ConfigPath
$baseUri = $ApiBaseUri.TrimEnd('/')
$models = @(Get-SDNextModels -ApiBaseUri $baseUri)
$checkpoint = Resolve-SDNextCheckpoint -Models $models -Config $config

try {
    $options = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/options" -Method Get -TimeoutSec 15
    $samplers = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/samplers" -Method Get -TimeoutSec 15
}
catch {
    throw "The SD.Next API responded partially but validation failed. Error: $($_.Exception.Message)"
}

[pscustomobject]@{
    Api = $baseUri
    CurrentCheckpoint = $options.sd_model_checkpoint
    RequiredCheckpoint = $checkpoint.title
    RequiredAutoV2 = $checkpoint.hash
    RequiredSha256 = $checkpoint.sha256
    AvailableModels = $models.Count
    AvailableSamplers = $samplers.Count
    Ready = $true
} | Format-List

