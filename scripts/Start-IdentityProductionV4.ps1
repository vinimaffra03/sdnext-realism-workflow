[CmdletBinding()]
param(
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\identity-production-v4-brazil.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\runs\identity-production-v4-brazil'),
    [ValidateSet('Pilot', 'CompositionPilot', 'Candidates')][string]$Mode = 'Pilot',
    [string[]]$ShotIds = @(),
    [ValidateSet('TXT', 'IPA', 'FID', 'POSE', 'IMG')][string]$Conditioning = 'IPA',
    [ValidateRange(1, 10)][int]$CandidateStart = 1,
    [ValidateRange(1, 10)][int]$CandidateEnd = 10,
    [ValidateRange(60, 7200)][int]$TimeoutSec = 5400
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$runner = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Invoke-IdentityProductionV4.ps1'))
$batchStatePath = Join-Path $OutputDirectory 'current-batch.json'

function Get-ActiveV4BatchProcess {
    param(
        [Parameter(Mandatory)][string]$RunnerPath,
        [Parameter(Mandatory)][string]$BatchOutputDirectory
    )

    $runnerPattern = [regex]::Escape($RunnerPath)
    $outputPattern = [regex]::Escape($BatchOutputDirectory)
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^(pwsh|powershell)(\.exe)?$' -and
            $_.CommandLine -match '(?i)-File\s+' -and
            $_.CommandLine -match $runnerPattern -and
            $_.CommandLine -match '(?i)-OutputDirectory\s+' -and
            $_.CommandLine -match $outputPattern
        } |
        Select-Object -First 1
}

$activeBatch = Get-ActiveV4BatchProcess -RunnerPath $runner -BatchOutputDirectory $OutputDirectory
if ($null -ne $activeBatch) {
    Write-Host "V4 batch is already running for this output directory (PID $($activeBatch.ProcessId))."
    if (Test-Path -LiteralPath $batchStatePath) {
        Write-Host "State: $batchStatePath"
    }
    return
}

$logRoot = Join-Path $OutputDirectory 'batch-logs'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $logRoot "v4-$stamp.stdout.log"
$stderr = Join-Path $logRoot "v4-$stamp.stderr.log"
$pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
$args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner, '-ApiBaseUri', $ApiBaseUri, '-ConfigPath', ([IO.Path]::GetFullPath($ConfigPath)), '-OutputDirectory', $OutputDirectory, '-Mode', $Mode, '-Conditioning', $Conditioning, '-CandidateStart', $CandidateStart, '-CandidateEnd', $CandidateEnd, '-TimeoutSec', $TimeoutSec)
if ($ShotIds.Count -gt 0) { $args += '-ShotIds'; $args += $ShotIds }
$process = Start-Process -FilePath $pwsh -ArgumentList $args -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
[ordered]@{
    pid = $process.Id; started_at = (Get-Date).ToString('o'); mode = $Mode; output_directory = $OutputDirectory
    config_path = [IO.Path]::GetFullPath($ConfigPath); conditioning = $Conditioning; shot_ids = @($ShotIds)
    candidate_start = $CandidateStart; candidate_end = $CandidateEnd; timeout_seconds = $TimeoutSec; stdout = $stdout; stderr = $stderr
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $batchStatePath -Encoding utf8
Write-Host "Started V4 batch PID $($process.Id)"
Write-Host "stdout: $stdout"
Write-Host "stderr: $stderr"
