[CmdletBinding()]
param(
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\baseline-n9.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\runs')
)

$ErrorActionPreference = 'Stop'

Write-Output 'Validating SD.Next and the required checkpoint...'
& (Join-Path $PSScriptRoot 'Test-SDNextConnection.ps1') -ApiBaseUri $ApiBaseUri -ConfigPath $ConfigPath

Write-Output 'Generating the approved baseline...'
& (Join-Path $PSScriptRoot 'Invoke-SDNextBaseline.ps1') -ApiBaseUri $ApiBaseUri -ConfigPath $ConfigPath -OutputDirectory $OutputDirectory
