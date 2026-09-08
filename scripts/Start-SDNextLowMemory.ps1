[CmdletBinding()]
param(
    [string]$PackagePath = 'D:\AIMODEL\StabilityMatrix-win-x64\Data\Packages\SD.Next',
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$RuntimeConfig = (Join-Path $PSScriptRoot '..\config\sdnext-batch-low-memory.json'),
    [string]$Checkpoint = 'CyberRealistic_V9_FP16 [22c7896047]',
    [ValidateRange(4, 64)]
    [double]$MinimumFreeVirtualGB = 6,
    [ValidateRange(60, 3600)]
    [int]$StartupTimeoutSec = 300,
    [ValidateRange(60, 3600)]
    [int]$ModelLoadTimeoutSec = 900
)

$ErrorActionPreference = 'Stop'
$baseUri = $ApiBaseUri.TrimEnd('/')
$python = Join-Path $PackagePath 'venv\Scripts\python.exe'
$launcher = Join-Path $PackagePath 'launch.py'
$runtime = (Resolve-Path -LiteralPath $RuntimeConfig).Path

if (-not (Test-Path -LiteralPath $python) -or -not (Test-Path -LiteralPath $launcher)) {
    throw "SD.Next was not found at '$PackagePath'. Pass the Stability Matrix SD.Next package directory with -PackagePath."
}

try {
    $null = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/version" -Method Get -TimeoutSec 3
    throw "An SD.Next server is already responding at $baseUri."
}
catch {
    if ($_.Exception.Message -like 'An SD.Next server is already*') {
        throw
    }
}

$os = Get-CimInstance Win32_OperatingSystem
$freeVirtualGB = [math]::Round($os.FreeVirtualMemory / 1MB, 2)
if ($freeVirtualGB -lt $MinimumFreeVirtualGB) {
    throw "Only $freeVirtualGB GB of virtual memory is free. Close unused applications or enlarge the Windows page file, then retry with at least $MinimumFreeVirtualGB GB free. This script will not close applications or change the page file automatically."
}

$logDirectory = Join-Path $PSScriptRoot '..\runs\runtime-logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$stdout = Join-Path $logDirectory "sdnext-low-memory-$stamp.stdout.log"
$stderr = Join-Path $logDirectory "sdnext-low-memory-$stamp.stderr.log"
$arguments = @(
    'launch.py',
    '--quick',
    '--medvram',
    '--use-cuda',
    '--config', $runtime,
    '--no-metadata'
)

Write-Host "Starting SD.Next without checkpoint autoload..."
$process = Start-Process -FilePath $python -ArgumentList $arguments -WorkingDirectory $PackagePath -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
$ready = $false
while ((Get-Date) -lt $deadline -and -not $process.HasExited) {
    Start-Sleep -Seconds 2
    try {
        $null = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/version" -Method Get -TimeoutSec 3
        $ready = $true
        break
    }
    catch {
        # The API is expected to reject connections while startup is incomplete.
    }
}

if (-not $ready) {
    $tail = @(Get-Content -LiteralPath $stdout -Tail 30 -ErrorAction SilentlyContinue) -join [Environment]::NewLine
    throw "SD.Next did not start. Process exit=$($process.HasExited). Log: $stdout`n$tail"
}

Write-Host "API ready. Loading checkpoint with state-dict offload enabled..."
$encodedCheckpoint = [Uri]::EscapeDataString($Checkpoint)
$loadUri = "$baseUri/sdapi/v1/checkpoint?sd_model_checkpoint=$encodedCheckpoint&dtype=float16"
try {
    $loadResult = Invoke-RestMethod -Uri $loadUri -Method Post -TimeoutSec $ModelLoadTimeoutSec
}
catch {
    $tail = @(Get-Content -LiteralPath $stdout -Tail 40 -ErrorAction SilentlyContinue) -join [Environment]::NewLine
    throw "Checkpoint loading failed. Log: $stdout`n$tail`n$($_.Exception.Message)"
}
if (-not $loadResult.ok) {
    throw "SD.Next responded but did not load '$Checkpoint'. Review $stdout."
}

$loaded = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/checkpoint" -Method Get -TimeoutSec 30
if (-not $loaded.class -or [string]$loaded.hash -notlike '*22c7896047*') {
    throw "Checkpoint verification failed. SD.Next reports title '$($loaded.title)', class '$($loaded.class)', hash '$($loaded.hash)'."
}

$state = [ordered]@{
    pid = $process.Id
    api = $baseUri
    checkpoint = $loaded.title
    checkpoint_hash = $loaded.hash
    stdout = $stdout
    stderr = $stderr
    started_at = (Get-Date).ToString('o')
}
$statePath = Join-Path $logDirectory 'current-sdnext.json'
$state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding utf8

Write-Host "SD.Next is ready at $baseUri (PID $($process.Id))."
Write-Host "Runtime state: $statePath"
Write-Host "Log: $stdout"
