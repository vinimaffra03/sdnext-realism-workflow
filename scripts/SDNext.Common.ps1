function Read-WorkflowConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $config = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json
    return $config
}

function Get-SDNextModels {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ApiBaseUri
    )

    $baseUri = $ApiBaseUri.TrimEnd('/')
    try {
        return Invoke-RestMethod -Uri "$baseUri/sdapi/v1/sd-models" -Method Get -TimeoutSec 15
    }
    catch {
        throw "SD.Next is not reachable at $baseUri. Launch SD.Next through Stability Matrix and try again. Error: $($_.Exception.Message)"
    }
}

function Resolve-SDNextCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Models,

        [Parameter(Mandatory)]
        [object]$Config
    )

    $expectedAutoV2 = [string]$Config.model_hash_autov2
    $expectedSha256 = [string]$Config.model_sha256
    $model = $Models |
        Where-Object {
            ($expectedAutoV2 -and $_.hash -ieq $expectedAutoV2) -or
            ($expectedSha256 -and $_.sha256 -ieq $expectedSha256)
        } |
        Select-Object -First 1

    if (-not $model) {
        $source = if ($Config.model_source) { [string]$Config.model_source } else { 'the model source documented in README.md' }
        throw "The required CyberRealistic checkpoint was not found. Expected AutoV2 $expectedAutoV2 or SHA-256 $expectedSha256. Install the exact pruned FP16 checkpoint from $source, refresh model discovery, and restart SD.Next."
    }

    return $model
}

function Save-SDNextImageResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Response,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    if (-not $Response.images -or $Response.images.Count -lt 1) {
        throw 'The SD.Next response did not contain an image.'
    }

    $encodedImage = [string]$Response.images[0]
    if ($encodedImage -match '^data:image/[^;]+;base64,') {
        $encodedImage = $encodedImage -replace '^data:image/[^;]+;base64,', ''
    }

    [IO.File]::WriteAllBytes($OutputPath, [Convert]::FromBase64String($encodedImage))
}

function Get-NonDestructiveOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string]$FileName
    )

    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $path = Join-Path $Directory $FileName
    if (-not (Test-Path -LiteralPath $path)) {
        return $path
    }

    $stem = [IO.Path]::GetFileNameWithoutExtension($FileName)
    $extension = [IO.Path]::GetExtension($FileName)
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return Join-Path $Directory "$stem-$timestamp$extension"
}
