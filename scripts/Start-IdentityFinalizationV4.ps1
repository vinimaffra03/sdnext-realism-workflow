[CmdletBinding()]
param(
    [string]$SelectionPath = (Join-Path $PSScriptRoot '..\config\identity-production-v4-selection.partial.json'),
    [string]$RunDirectory = (Join-Path $PSScriptRoot '..\runs\identity-production-v4-brazil'),
    [ValidateRange(60, 7200)][int]$TimeoutSec = 5400,
    [switch]$AllowPartial,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$selection = [IO.Path]::GetFullPath($SelectionPath)
$runRoot = [IO.Path]::GetFullPath($RunDirectory)
$finalizer = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Finalize-IdentityProductionV4.ps1'))
$generator = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'Invoke-IdentityProductionV4.ps1'))
if (-not (Test-Path -LiteralPath $selection)) { throw "Selection file not found: $selection" }
if (-not (Test-Path -LiteralPath $runRoot)) { throw "Run directory not found: $runRoot" }

$runPattern = [regex]::Escape($runRoot)
$finalizerPattern = [regex]::Escape($finalizer)
$generatorPattern = [regex]::Escape($generator)
$active = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match '^(pwsh|powershell)(\.exe)?$' -and
        $_.CommandLine -match '(?i)-File\s+' -and
        (($_.CommandLine -match $finalizerPattern -and $_.CommandLine -match '(?i)-RunDirectory\s+') -or
         ($_.CommandLine -match $generatorPattern -and $_.CommandLine -match '(?i)-OutputDirectory\s+')) -and
        $_.CommandLine -match $runPattern
    } |
    Select-Object -First 1

if ($null -ne $active) {
    Write-Host "A V4 generator or finalizer already owns this run directory (PID $($active.ProcessId))."
    return
}

$logRoot = Join-Path $runRoot 'finalization-logs'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $logRoot "finalize-$stamp.stdout.log"
$stderr = Join-Path $logRoot "finalize-$stamp.stderr.log"
$pwsh = (Get-Command pwsh.exe -ErrorAction Stop).Source
$arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $finalizer, '-SelectionPath', $selection, '-RunDirectory', $runRoot, '-TimeoutSec', $TimeoutSec)
if ($AllowPartial) { $arguments += '-AllowPartial' }
if ($Force) { $arguments += '-Force' }
$process = Start-Process -FilePath $pwsh -ArgumentList $arguments -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden

[ordered]@{
    pid = $process.Id
    started_at = (Get-Date).ToString('o')
    selection_path = $selection
    run_directory = $runRoot
    timeout_seconds = $TimeoutSec
    allow_partial = [bool]$AllowPartial
    force = [bool]$Force
    stdout = $stdout
    stderr = $stderr
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runRoot 'current-finalization.json') -Encoding utf8

Write-Host "Started V4 finalization PID $($process.Id)"
Write-Host "stdout: $stdout"
Write-Host "stderr: $stderr"
