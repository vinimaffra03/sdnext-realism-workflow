[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\runs\identity-production-v2'),
    [ValidateRange(1, 10)][int]$StartShot = 1,
    [ValidateRange(1, 10)][int]$EndShot = 10,
    [ValidateRange(60, 7200)][int]$TimeoutSec = 1800
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runner = Join-Path $PSScriptRoot 'Invoke-IdentityStressTest.ps1'
$output = [IO.Path]::GetFullPath($OutputDirectory)
$logDirectory = Join-Path $output 'batch-logs'
$statePath = Join-Path $output 'current-batch.json'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

if (Test-Path -LiteralPath $statePath) {
    $prior = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $priorProcess = Get-Process -Id ([int]$prior.pid) -ErrorAction SilentlyContinue
    if ($priorProcess -and -not $priorProcess.HasExited) {
        throw "A production batch is already running with PID $($prior.pid)."
    }
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $logDirectory "identity-production-$stamp.stdout.log"
$stderr = Join-Path $logDirectory "identity-production-$stamp.stderr.log"
$hostExecutable = (Get-Process -Id $PID).Path

function Quote-PowerShellLiteral([string]$Value) {
    return "'" + $Value.Replace("'", "''") + "'"
}

$command = @(
    '& ' + (Quote-PowerShellLiteral $runner),
    '-OutputDirectory ' + (Quote-PowerShellLiteral $output),
    "-StartShot $StartShot",
    "-EndShot $EndShot",
    '-Stages TXT,POS,FIN',
    "-TimeoutSec $TimeoutSec"
) -join ' '
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))

$process = Start-Process -FilePath $hostExecutable `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand) `
    -WorkingDirectory $repoRoot `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -PassThru

$state = [ordered]@{
    pid = $process.Id
    started_at = (Get-Date).ToString('o')
    output_directory = $output
    stages = @('TXT', 'POS', 'FIN')
    start_shot = $StartShot
    end_shot = $EndShot
    stdout = $stdout
    stderr = $stderr
    resumable_command = $command
}
[IO.File]::WriteAllText($statePath, ($state | ConvertTo-Json -Depth 5), [Text.UTF8Encoding]::new($false))

Write-Host "Production batch started with PID $($process.Id)."
Write-Host "State: $statePath"
Write-Host "Log: $stdout"
Write-Host "Outputs: $output"
