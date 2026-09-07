[CmdletBinding()]
param(
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\baseline-n9.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\runs'),
    [string]$FileName = 'baseline-n9-reproduction.png'
)

$ErrorActionPreference = 'Stop'
$configPathResolved = (Resolve-Path -LiteralPath $ConfigPath).Path
$config = Get-Content -LiteralPath $configPathResolved -Raw | ConvertFrom-Json
$baseUri = $ApiBaseUri.TrimEnd('/')
$apiUri = "$baseUri/sdapi/v1/txt2img"

try {
    $models = @(Invoke-RestMethod -Uri "$baseUri/sdapi/v1/sd-models" -Method Get -TimeoutSec 15)
}
catch {
    throw "SD.Next não está acessível em $baseUri. Inicie-o no Stability Matrix. Erro: $($_.Exception.Message)"
}

if (-not ($models | Where-Object { $_.title -eq $config.model -or $_.model_name -like 'CyberRealistic_V9_FP16*' })) {
    Write-Warning "O checkpoint registrado não apareceu na lista da API: $($config.model)"
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputPath = Join-Path $OutputDirectory $FileName
if (Test-Path -LiteralPath $outputPath) {
    $stem = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [IO.Path]::GetExtension($FileName)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $outputPath = Join-Path $OutputDirectory "$stem-$timestamp$extension"
}

$payload = [ordered]@{
    sd_model_checkpoint = [string]$config.model
    prompt = [string]$config.prompt
    negative_prompt = [string]$config.negative_prompt
    seed = [long]$config.seed
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
    detailer_enabled = [bool]$config.detailer_enabled
    enable_hr = [bool]$config.enable_hr
    save_images = $false
    send_images = $true
    do_not_save_samples = $true
}

$started = Get-Date
$response = Invoke-RestMethod -Uri $apiUri -Method Post -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 6) -TimeoutSec 900
if (-not $response.images -or $response.images.Count -lt 1) {
    throw 'A resposta do SD.Next não contém uma imagem.'
}

$encodedImage = [string]$response.images[0]
if ($encodedImage -match '^data:image/[^;]+;base64,') {
    $encodedImage = $encodedImage -replace '^data:image/[^;]+;base64,', ''
}
[IO.File]::WriteAllBytes($outputPath, [Convert]::FromBase64String($encodedImage))

$elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
$metadata = [ordered]@{
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    output_file = [IO.Path]::GetFileName($outputPath)
    elapsed_seconds = $elapsed
    api_base_uri = $baseUri
    config_source = $configPathResolved
    parameters = $payload
}
$metadataPath = [IO.Path]::ChangeExtension($outputPath, '.json')
$metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

Write-Output "Imagem: $outputPath"
Write-Output "Metadados: $metadataPath"
Write-Output "Tempo: $elapsed s"

