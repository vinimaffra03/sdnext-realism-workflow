[CmdletBinding()]
param(
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\baseline-n9.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\runs'),
    [string]$FileName = 'baseline-n9-reproduction.png'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'SDNext.Common.ps1')

$configPathResolved = (Resolve-Path -LiteralPath $ConfigPath).Path
$config = Read-WorkflowConfig -Path $configPathResolved
$baseUri = $ApiBaseUri.TrimEnd('/')
$apiUri = "$baseUri/sdapi/v1/txt2img"
$models = @(Get-SDNextModels -ApiBaseUri $baseUri)
$checkpoint = Resolve-SDNextCheckpoint -Models $models -Config $config
$outputPath = Get-NonDestructiveOutputPath -Directory $OutputDirectory -FileName $FileName

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
Save-SDNextImageResponse -Response $response -OutputPath $outputPath

$elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
$metadata = [ordered]@{
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    output_file = [IO.Path]::GetFileName($outputPath)
    elapsed_seconds = $elapsed
    api_base_uri = $baseUri
    config_source = $configPathResolved
    resolved_checkpoint = [ordered]@{
        title = $checkpoint.title
        hash = $checkpoint.hash
        sha256 = $checkpoint.sha256
    }
    parameters = $payload
}
$metadataPath = [IO.Path]::ChangeExtension($outputPath, '.json')
$metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

Write-Output "Image: $outputPath"
Write-Output "Metadata: $metadataPath"
Write-Output "Elapsed time: $elapsed seconds"

