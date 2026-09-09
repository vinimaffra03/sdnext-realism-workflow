[CmdletBinding()]
param(
    [string]$PackagePath = 'D:\AIMODEL\StabilityMatrix-win-x64\Data\Packages\SD.Next',
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$RuntimeConfig = (Join-Path $PSScriptRoot '..\config\sdnext-batch-low-memory.json'),
    [string]$Checkpoint = 'CyberRealistic_V9_FP16 [22c7896047]',
    [string]$SourceCheckpoint = 'D:\AIMODEL\StabilityMatrix-win-x64\Data\Packages\SD.Next\models\Stable-diffusion\CyberRealistic_V9_FP16.safetensors',
    [string]$ExpectedSourceSha256 = '22C789604729ED346F745497B99EB62DF116E7B50F671E4EDF4058D382B0A235',
    [ValidateSet('medvram', 'lowvram')]
    [string]$MemoryMode = 'medvram',
    [ValidateSet('BF16', 'FP16', 'FP32')]
    [string]$ComputeDType = 'BF16',
    [ValidateRange(4, 64)]
    [double]$MinimumFreeVirtualGB = 6,
    [ValidateRange(60, 3600)]
    [int]$StartupTimeoutSec = 300,
    [ValidateRange(60, 3600)]
    [int]$ModelLoadTimeoutSec = 900,
    # Keep the Control tab initialized even for API-only runs. SD.Next registers
    # selectable Control scripts (including FaceSwap) while building this tab.
    [string]$DisabledUiTabs = 'img2img,video,extras,caption,models,gallery,info,extensions,update,config,history,storage,monitor,onnx,system'
)

$ErrorActionPreference = 'Stop'
$baseUri = $ApiBaseUri.TrimEnd('/')
$python = Join-Path $PackagePath 'venv\Scripts\python.exe'
$launcher = Join-Path $PackagePath 'launch.py'
$runtime = (Resolve-Path -LiteralPath $RuntimeConfig).Path

if (-not (Test-Path -LiteralPath $python) -or -not (Test-Path -LiteralPath $launcher)) {
    throw "SD.Next was not found at '$PackagePath'. Pass the Stability Matrix SD.Next package directory with -PackagePath."
}

if (-not (Test-Path -LiteralPath $SourceCheckpoint -PathType Leaf)) {
    throw "The source checkpoint was not found at '$SourceCheckpoint'."
}
$actualSourceSha256 = (Get-FileHash -LiteralPath $SourceCheckpoint -Algorithm SHA256).Hash
if ($actualSourceSha256 -ne $ExpectedSourceSha256) {
    throw "Source checkpoint hash mismatch. Expected '$ExpectedSourceSha256', found '$actualSourceSha256'."
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
$runtimeCopy = Join-Path $logDirectory "sdnext-low-memory-$stamp.config.json"
Copy-Item -LiteralPath $runtime -Destination $runtimeCopy -Force
$runtimeRoot = Join-Path $PSScriptRoot '..\runs\sdnext-runtime'
$processTemp = Join-Path $runtimeRoot 'temp'
$cacheRoot = Join-Path $runtimeRoot 'cache'
$childEnvironment = @{
    TEMP = $processTemp
    TMP = $processTemp
    TMPDIR = $processTemp
    GRADIO_TEMP_DIR = $processTemp
    HF_HOME = (Join-Path $cacheRoot 'huggingface')
    HF_HUB_CACHE = (Join-Path $cacheRoot 'huggingface\hub')
    HUGGINGFACE_HUB_CACHE = (Join-Path $cacheRoot 'huggingface\hub')
    HF_XET_CACHE = (Join-Path $cacheRoot 'huggingface\xet')
    TRANSFORMERS_CACHE = (Join-Path $cacheRoot 'huggingface\transformers')
    TORCH_HOME = (Join-Path $cacheRoot 'torch')
    TORCHINDUCTOR_CACHE_DIR = (Join-Path $cacheRoot 'torch-inductor')
    TORCH_EXTENSIONS_DIR = (Join-Path $cacheRoot 'torch-extensions')
    TRITON_CACHE_DIR = (Join-Path $cacheRoot 'triton')
    CUDA_CACHE_PATH = (Join-Path $cacheRoot 'nvidia-compute')
    NUMBA_CACHE_DIR = (Join-Path $cacheRoot 'numba')
    PYTHONPYCACHEPREFIX = (Join-Path $cacheRoot 'pycache')
    XDG_CACHE_HOME = $cacheRoot
    PIP_CACHE_DIR = (Join-Path $cacheRoot 'pip')
    UV_CACHE_DIR = (Join-Path $cacheRoot 'uv')
}
@($runtimeRoot, $processTemp, $cacheRoot) + @($childEnvironment.Values) |
    Select-Object -Unique |
    ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
$arguments = @(
    'launch.py',
    '--quick',
    "--$MemoryMode",
    '--use-cuda',
    '--safe',
    '--disable', $DisabledUiTabs,
    '--config', $runtimeCopy,
    '--no-metadata'
)

function Stop-LaunchedServer {
    param([string]$Reason)

    if ($null -eq $script:process) {
        return
    }

    Write-Warning "$Reason Shutting down the SD.Next instance started by this script."
    try {
        $null = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/shutdown" -Method Post -TimeoutSec 15
    }
    catch {
        Write-Warning "Graceful shutdown request failed: $($_.Exception.Message)"
    }

    $shutdownDeadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $shutdownDeadline) {
        $listener = Get-NetTCPConnection -LocalPort ([uri]$baseUri).Port -State Listen -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -eq $listener) {
            return
        }
        Start-Sleep -Seconds 1
    }

    $listenerPid = [int]$listener.OwningProcess
    $listenerProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$listenerPid" -ErrorAction SilentlyContinue
    if ($null -ne $listenerProcess -and
        [int]$listenerProcess.ParentProcessId -eq [int]$script:process.Id -and
        $listenerProcess.CommandLine -like '*launch.py*' -and
        $listenerProcess.CommandLine -like "*$runtimeCopy*") {
        Write-Warning "SD.Next did not exit after 30 seconds; stopping verified listener PID $listenerPid."
        Stop-Process -Id $listenerPid -Force
    }
    else {
        Write-Warning "The process still listening on $baseUri could not be verified as this launch; it was not stopped."
    }
}

Write-Host "Starting SD.Next without checkpoint autoload..."
$startParameters = @{
    FilePath = $python
    ArgumentList = $arguments
    WorkingDirectory = $PackagePath
    WindowStyle = 'Hidden'
    RedirectStandardOutput = $stdout
    RedirectStandardError = $stderr
    PassThru = $true
}
if ((Get-Command Start-Process).Parameters.ContainsKey('Environment')) {
    $startParameters.Environment = $childEnvironment
    $script:process = Start-Process @startParameters
}
else {
    $previousEnvironment = @{}
    try {
        foreach ($entry in $childEnvironment.GetEnumerator()) {
            $previousEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
        }
        $script:process = Start-Process @startParameters
    }
    finally {
        foreach ($entry in $previousEnvironment.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
        }
    }
}
$deadline = (Get-Date).AddSeconds($StartupTimeoutSec)
$ready = $false
while ((Get-Date) -lt $deadline -and -not $script:process.HasExited) {
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
    Stop-LaunchedServer -Reason 'Startup failed.'
    throw "SD.Next did not start. Process exit=$($script:process.HasExited). Log: $stdout`n$tail"
}

Write-Host "API ready. Loading the verified FP16 checkpoint with $ComputeDType compute and $MemoryMode model placement..."
$encodedCheckpoint = [Uri]::EscapeDataString($Checkpoint)
$loadUri = "$baseUri/sdapi/v1/checkpoint?sd_model_checkpoint=$encodedCheckpoint&dtype=$ComputeDType"
try {
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
    $expectedShortHash = $ExpectedSourceSha256.Substring(0, 10)
    if (-not $loaded.class -or [string]$loaded.hash -ine $expectedShortHash) {
        throw "Checkpoint verification failed. SD.Next reports title '$($loaded.title)', class '$($loaded.class)', hash '$($loaded.hash)'."
    }
}
catch {
    $failure = $_
    Stop-LaunchedServer -Reason 'Checkpoint loading failed.'
    throw $failure
}

$listener = Get-NetTCPConnection -LocalPort ([uri]$baseUri).Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -eq $listener) {
    Stop-LaunchedServer -Reason 'Listener verification failed.'
    throw "SD.Next loaded the checkpoint but no listener was found at $baseUri."
}
$listenerPid = [int]$listener.OwningProcess
$listenerProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$listenerPid" -ErrorAction SilentlyContinue
if ($null -eq $listenerProcess -or
    [int]$listenerProcess.ParentProcessId -ne [int]$script:process.Id -or
    $listenerProcess.CommandLine -notlike '*launch.py*' -or
    $listenerProcess.CommandLine -notlike "*$runtimeCopy*") {
    Stop-LaunchedServer -Reason 'Listener verification failed.'
    throw "The process listening at $baseUri could not be verified as the SD.Next instance started by this script."
}

$state = [ordered]@{
    pid = $listenerPid
    launcher_pid = $script:process.Id
    api = $baseUri
    checkpoint = $loaded.title
    checkpoint_hash = $loaded.hash
    source_checkpoint = $SourceCheckpoint
    source_checkpoint_hash = $actualSourceSha256
    stdout = $stdout
    stderr = $stderr
    runtime_config = $runtimeCopy
    runtime_root = $runtimeRoot
    memory_mode = $MemoryMode
    compute_dtype = $ComputeDType
    started_at = (Get-Date).ToString('o')
}
$statePath = Join-Path $logDirectory 'current-sdnext.json'
$state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding utf8

Write-Host "SD.Next is ready at $baseUri (PID $listenerPid)."
Write-Host "Runtime state: $statePath"
Write-Host "Log: $stdout"
