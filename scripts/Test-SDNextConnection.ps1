[CmdletBinding()]
param(
    [string]$ApiBaseUri = 'http://127.0.0.1:7860'
)

$ErrorActionPreference = 'Stop'
$baseUri = $ApiBaseUri.TrimEnd('/')

try {
    $options = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/options" -Method Get -TimeoutSec 15
    $models = @(Invoke-RestMethod -Uri "$baseUri/sdapi/v1/sd-models" -Method Get -TimeoutSec 15)
    $samplers = @(Invoke-RestMethod -Uri "$baseUri/sdapi/v1/samplers" -Method Get -TimeoutSec 15)
}
catch {
    throw "Não foi possível acessar o SD.Next em $baseUri. Inicie o pacote no Stability Matrix e tente novamente. Erro: $($_.Exception.Message)"
}

[pscustomobject]@{
    Api = $baseUri
    CurrentCheckpoint = $options.sd_model_checkpoint
    AvailableModels = $models.Count
    AvailableSamplers = $samplers.Count
    BaselineModelFound = [bool]($models | Where-Object { $_.title -like 'CyberRealistic_V9_FP16*' })
} | Format-List

