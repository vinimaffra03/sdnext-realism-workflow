[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,

    [string]$ExpectedCommit = '684940e015911efab2911667231946d91fef9f50',

    [switch]$AllowDifferentRevision
)

$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path -LiteralPath $PackagePath).Path
$apiPath = Join-Path $packageRoot 'modules\api\api.py'
$controlPath = Join-Path $packageRoot 'modules\api\control.py'
$pythonPath = Join-Path $packageRoot 'venv\Scripts\python.exe'

foreach ($requiredPath in @($apiPath, $controlPath, $pythonPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required SD.Next file was not found: $requiredPath"
    }
}

$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
    $actualCommit = (& git -C $packageRoot rev-parse HEAD 2>$null).Trim()
    if ($LASTEXITCODE -eq 0 -and $actualCommit -and $actualCommit -ne $ExpectedCommit) {
        $message = "This patch was validated against SD.Next commit $ExpectedCommit, but the package is at $actualCommit."
        if (-not $AllowDifferentRevision) {
            throw "$message Re-run with -AllowDifferentRevision only after reviewing the upstream diff."
        }
        Write-Warning $message
    }
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$backupRoot = Join-Path $packageRoot ('.workflow-backup\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$changedFiles = [System.Collections.Generic.List[string]]::new()

function Update-TextFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][scriptblock]$Transform
    )

    $original = [IO.File]::ReadAllText($Path)
    $updated = & $Transform $original
    if ($updated -eq $original) {
        return
    }

    if ($PSCmdlet.ShouldProcess($Path, 'Apply the tested SD.Next API compatibility patch')) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        Copy-Item -LiteralPath $Path -Destination (Join-Path $backupRoot ([IO.Path]::GetFileName($Path)))
        [IO.File]::WriteAllText($Path, $updated, $utf8NoBom)
        $changedFiles.Add($Path)
    }
}

Update-TextFile -Path $apiPath -Transform {
    param($text)
    $old = 'self.add_api_route("/sdapi/v1/preprocess", self.process.post_preprocess, methods=["POST"], response_model=models.ResPreprocess, tags=["Processing"])'
    $new = 'self.add_api_route("/sdapi/v1/preprocess", self.process.post_preprocess, methods=["POST"], response_model=process.ResPreprocess, tags=["Processing"])'
    if ($text.Contains($new)) { return $text }
    if (-not $text.Contains($old)) {
        throw 'The expected preprocess route was not found in modules/api/api.py.'
    }
    return $text.Replace($old, $new)
}

Update-TextFile -Path $controlPath -Transform {
    param($text)
    $updated = $text
    $oldImport = 'from modules import errors, shared, processing_helpers'
    $newImport = 'from modules import devices, errors, shared, processing_helpers'
    if (-not $updated.Contains($newImport)) {
        if (-not $updated.Contains($oldImport)) {
            throw 'The expected modules import was not found in modules/api/control.py.'
        }
        $updated = $updated.Replace($oldImport, $newImport)
    }

    $oldBlock = @'
    def prepare_control(self, req):
        from modules.control.unit import Unit, unit_types
        req.units = []
'@
    $newBlock = @'
    def prepare_control(self, req):
        from modules.control import unit as control_unit
        from modules.control.unit import Unit, unit_types
        # API-created units otherwise inherit the module defaults of None and
        # load ControlNet weights as FP32. Match the active pipeline dtype and
        # device before Unit.__init__ performs the model load.
        control_unit.default_device = devices.device
        control_unit.default_dtype = devices.dtype
        req.units = []
'@
    if (-not $updated.Contains('control_unit.default_dtype = devices.dtype')) {
        if (-not $updated.Contains($oldBlock)) {
            throw 'The expected prepare_control block was not found in modules/api/control.py.'
        }
        $updated = $updated.Replace($oldBlock, $newBlock)
    }
    return $updated
}

if ($WhatIfPreference) {
    return
}

& $pythonPath -m py_compile $apiPath $controlPath
if ($LASTEXITCODE -ne 0) {
    throw 'Python syntax validation failed after patching SD.Next.'
}

if ($changedFiles.Count -eq 0) {
    Write-Host 'The tested SD.Next API compatibility patch is already applied.'
} else {
    Write-Host "Patched $($changedFiles.Count) SD.Next file(s). Backups: $backupRoot"
}
Write-Host 'Restart SD.Next before running the OpenPose stage.'
