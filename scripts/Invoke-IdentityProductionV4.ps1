[CmdletBinding()]
param(
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\identity-production-v4-brazil.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\runs\identity-production-v4-brazil'),
    [ValidateSet('Pilot', 'CompositionPilot', 'Candidates')]
    [string]$Mode = 'Pilot',
    [string[]]$ShotIds = @(),
    [ValidateSet('TXT', 'IPA', 'FID', 'POSE')]
    [string]$Conditioning = 'IPA',
    [ValidateRange(1, 10)]
    [int]$CandidateStart = 1,
    [ValidateRange(1, 10)]
    [int]$CandidateEnd = 10,
    [ValidateRange(60, 7200)]
    [int]$TimeoutSec = 5400,
    [switch]$ValidateOnly,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$config = Get-Content -LiteralPath (Resolve-Path -LiteralPath $ConfigPath).Path -Raw | ConvertFrom-Json
$baseUri = $ApiBaseUri.TrimEnd('/')
$txt2imgUri = "$baseUri/sdapi/v1/txt2img"
$controlUri = "$baseUri/sdapi/v1/control"
$preprocessUri = "$baseUri/sdapi/v1/preprocess"
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$requestRoot = Join-Path $outputRoot 'requests'
$responseRoot = Join-Path $outputRoot 'response-info'
$poseRoot = Join-Path $outputRoot 'pose-maps'
New-Item -ItemType Directory -Path $outputRoot, $requestRoot, $responseRoot, $poseRoot -Force | Out-Null

$referencePath = (Resolve-Path -LiteralPath (Join-Path $repoRoot ([string]$config.subject.reference_image))).Path
$referenceHash = (Get-FileHash -LiteralPath $referencePath -Algorithm SHA256).Hash
if ($referenceHash -ine [string]$config.subject.reference_sha256) {
    throw "Reference hash mismatch. Expected $($config.subject.reference_sha256), found $referenceHash."
}
$referenceBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($referencePath))
$manifestPath = Join-Path $outputRoot 'manifest.csv'
$script:manifest = if (Test-Path -LiteralPath $manifestPath) { @(Import-Csv -LiteralPath $manifestPath) } else { @() }

function Wait-SDNextIdle {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $progress = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/progress?skip_current_image=true" -TimeoutSec 15
        if (-not [string]$progress.state.job) { return }
        if ([int]$progress.state.sampling_steps -eq 0 -and [double]$progress.progress -eq 0) { return }
        Start-Sleep -Seconds 10
    }
    throw "SD.Next remained busy longer than $TimeoutSec seconds."
}

function Save-ApiImage {
    param([Parameter(Mandatory)][string]$Encoded, [Parameter(Mandatory)][string]$Path)
    $clean = $Encoded -replace '^data:image/[^;]+;base64,', ''
    [IO.File]::WriteAllBytes($Path, [Convert]::FromBase64String($clean))
    if ((Get-Item -LiteralPath $Path).Length -lt 4096) { throw "Generated image is unexpectedly small: $Path" }
}

function Save-Manifest {
    param([string]$JobId, [object]$Shot, [int]$Candidate, [string]$Stage, [long]$Seed, [string]$File, [string]$Status, [double]$Elapsed, [string]$ErrorMessage = '')
    $script:manifest = @($script:manifest | Where-Object { $_.job_id -ne $JobId })
    $path = Join-Path $outputRoot $File
    $hash = if (Test-Path -LiteralPath $path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash } else { '' }
    $script:manifest += [pscustomobject][ordered]@{
        job_id = $JobId; shot = $Shot.id; candidate = $Candidate; conditioning = $Stage; seed = $Seed
        file = $File; status = $Status; elapsed_seconds = $Elapsed.ToString('0.0', [Globalization.CultureInfo]::InvariantCulture)
        width = $Shot.width; height = $Shot.height; checkpoint = $config.model.checkpoint
        sampler = $config.model.sampler; scheduler = $config.model.scheduler; cfg = $config.model.cfg; steps = $config.model.steps
        reference_sha256 = $config.subject.reference_sha256; output_sha256 = $hash; error = $ErrorMessage; updated_at = (Get-Date).ToString('o')
    }
    $script:manifest | Sort-Object shot, candidate, conditioning | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding utf8
}

function Write-Gallery {
    $cards = foreach ($row in @($script:manifest | Where-Object { $_.status -in @('ok', 'existing') })) {
        $safeFile = [Net.WebUtility]::HtmlEncode([string]$row.file)
        $caption = [Net.WebUtility]::HtmlEncode("$($row.job_id) | seed $($row.seed) | $($row.width)x$($row.height)")
        "<figure><a href='$safeFile'><img loading='lazy' src='$safeFile'></a><figcaption>$caption</figcaption></figure>"
    }
    $html = @"
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Identity Production V4</title>
<style>body{font-family:Inter,Arial;background:#111;color:#eee;margin:24px}h1{font-size:24px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:18px}figure{margin:0;background:#1d1d1d;padding:10px;border-radius:8px}img{width:100%;height:360px;object-fit:contain;background:#080808}figcaption{font-size:12px;line-height:1.4;margin-top:8px;overflow-wrap:anywhere}</style></head><body>
<h1>Identity Production V4 — Brazilian environments</h1><p>Reference: fictional adult N9 brunette. Open images at full resolution for visual QA.</p><div class="grid">$($cards -join "`n")</div></body></html>
"@
    $html | Set-Content -LiteralPath (Join-Path $outputRoot 'report.html') -Encoding utf8
}

function New-Prompt {
    param([object]$Shot)
    $priority = if ($Shot.priority_prompt) { "$($Shot.priority_prompt), " } else { '' }
    return "one person, $priority$($config.identity.prompt), $($Shot.framing), $($Shot.scene), wearing $($Shot.outfit), $($Shot.pose), $($Shot.expression), $($config.realism_prompt), $($config.sensuality_prompt)"
}

function New-NegativePrompt {
    param([object]$Shot)
    if ($Shot.negative_additions) { return "$($config.negative_prompt), $($Shot.negative_additions)" }
    return [string]$config.negative_prompt
}

function New-TxtPayload {
    param([object]$Shot, [long]$Seed, [string]$Stage)
    $payload = [ordered]@{
        prompt = New-Prompt -Shot $Shot; negative_prompt = New-NegativePrompt -Shot $Shot; seed = $Seed
        batch_size = 1; n_iter = 1; steps = [int]$config.model.steps; width = [int]$Shot.width; height = [int]$Shot.height
        sampler_name = [string]$config.model.sampler; schedulers_sigma = [string]$config.model.scheduler
        cfg_scale = [double]$config.model.cfg; guidance_scale = [double]$config.model.cfg; vae_type = [string]$config.model.vae
        detailer_enabled = $false; enable_hr = $false; save_images = $false; send_images = $true; do_not_save_samples = $true
    }
    if ($Stage -eq 'IPA') {
        $payload.ip_adapter = @([ordered]@{
            adapter = [string]$config.identity.ip_adapter; images = @($referenceBase64); masks = @(); scale = [double]$config.identity.ip_scale
            start = [double]$config.identity.ip_start; end = [double]$config.identity.ip_end; crop = [bool]$config.identity.ip_crop
        })
    }
    elseif ($Stage -eq 'FID') {
        $payload.script_name = 'Face: Multiple ID Transfers'
        $payload.script_args = @('FaceID', @($referenceBase64), 'ReSwapper 256 0.2', $false, [string]$config.identity.faceid_model, $false, $true, [double]$config.identity.faceid_strength, [double]$config.identity.faceid_structure, 1.0, 0.5, $true, 'PhotoMaker v2', 'person', 1.0, 0.5, $true)
    }
    return $payload
}

function New-PosePayload {
    param([object]$Shot, [long]$Seed, [string]$PoseBase64)
    $unit = [ordered]@{
        process = 'None'; model = [string]$config.identity.openpose_model
        strength = [double]$config.identity.openpose_strength; start = [double]$config.identity.openpose_start; end = [double]$config.identity.openpose_end
        unit_type = 'controlnet'; process_params = [ordered]@{}; override = $PoseBase64
    }
    return [ordered]@{
        input_type = 0; prompt = New-Prompt -Shot $Shot; negative_prompt = New-NegativePrompt -Shot $Shot
        steps = [int]$config.model.steps; sampler_name = [string]$config.model.sampler; schedulers_sigma = [string]$config.model.scheduler
        seed = $Seed; guidance_scale = [double]$config.model.cfg; cfg_scale = [double]$config.model.cfg; vae_type = [string]$config.model.vae
        width_before = [int]$Shot.width; height_before = [int]$Shot.height; batch_count = 1; batch_size = 1
        save_images = $false; send_images = $true; unit_type = 'controlnet'; inputs = @(); control = @($unit)
    }
}

function Invoke-Job {
    param([object]$Shot, [int]$Candidate, [string]$Stage)
    $seed = [long]$Shot.seed + ([long]($Candidate - 1) * [long]$config.candidate_policy.seed_stride)
    $jobId = "$($Shot.id)-C$($Candidate.ToString('00'))-$Stage"
    $file = "$jobId.png"
    $path = Join-Path $outputRoot $file
    if ((Test-Path -LiteralPath $path) -and -not $Force) {
        Write-Host "[$jobId] Existing image; skipping."
        Save-Manifest -JobId $jobId -Shot $Shot -Candidate $Candidate -Stage $Stage -Seed $seed -File $file -Status 'existing' -Elapsed 0
        return
    }
    $uri = $txt2imgUri
    if ($Stage -eq 'POSE') {
        if (-not $Shot.pose_source) { throw "$($Shot.id) has no authorized complete pose_source; POSE was refused." }
        $sourcePath = (Resolve-Path -LiteralPath (Join-Path $repoRoot ([string]$Shot.pose_source))).Path
        $pre = [ordered]@{ image = [Convert]::ToBase64String([IO.File]::ReadAllBytes($sourcePath)); model = [string]$config.identity.openpose_preprocessor; params = [ordered]@{ include_body = $true; include_hand = $true; include_face = $false } }
        Wait-SDNextIdle
        $preResponse = Invoke-RestMethod -Uri $preprocessUri -Method Post -ContentType 'application/json' -Body ($pre | ConvertTo-Json -Depth 20) -TimeoutSec $TimeoutSec
        if (-not $preResponse.image) { throw "OpenPose preprocessing returned no map for $($Shot.id)." }
        $poseMap = Join-Path $poseRoot "$($Shot.id)-C$($Candidate.ToString('00'))-openpose.png"
        Save-ApiImage -Encoded ([string]$preResponse.image) -Path $poseMap
        $payload = New-PosePayload -Shot $Shot -Seed $seed -PoseBase64 ([Convert]::ToBase64String([IO.File]::ReadAllBytes($poseMap)))
        $uri = $controlUri
    }
    else { $payload = New-TxtPayload -Shot $Shot -Seed $seed -Stage $Stage }
    $payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $requestRoot "$jobId.json") -Encoding utf8
    $started = Get-Date
    try {
        Write-Host "[$jobId] Generating..."
        Wait-SDNextIdle
        $response = Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json' -Body ($payload | ConvertTo-Json -Depth 20) -TimeoutSec $TimeoutSec
        if (-not $response.images -or $response.images.Count -lt 1) { throw 'SD.Next returned no image.' }
        Save-ApiImage -Encoded ([string]$response.images[0]) -Path $path
        [ordered]@{ job_id = $jobId; generated_at = (Get-Date).ToString('o'); info = [string]$response.info; html_info = [string]$response.html_info } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $responseRoot "$jobId.json") -Encoding utf8
        Save-Manifest -JobId $jobId -Shot $Shot -Candidate $Candidate -Stage $Stage -Seed $seed -File $file -Status 'ok' -Elapsed ((Get-Date) - $started).TotalSeconds
    }
    catch {
        Save-Manifest -JobId $jobId -Shot $Shot -Candidate $Candidate -Stage $Stage -Seed $seed -File $file -Status 'failed' -Elapsed ((Get-Date) - $started).TotalSeconds -ErrorMessage $_.Exception.Message
        throw
    }
    finally { Write-Gallery }
}

if ($CandidateStart -gt $CandidateEnd) { throw 'CandidateStart must not exceed CandidateEnd.' }
$options = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/options" -TimeoutSec 30
if ([string]$options.sd_model_checkpoint -notmatch '22c7896047') { throw "Wrong checkpoint selected: $($options.sd_model_checkpoint)" }
$availableAdapters = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/ip-adapters" -TimeoutSec 30
if (-not ($availableAdapters -contains 'Plus Face')) { throw "Required IP-Adapter Plus Face is unavailable. Reported adapters: $($availableAdapters -join ', ')" }

$shotsById = @{}; foreach ($shot in $config.shots) { $shotsById[[string]$shot.id] = $shot }
if ($Mode -eq 'Pilot') {
    $jobs = @(
        [pscustomobject]@{ shot = $shotsById['P01']; candidate = 1; stage = 'TXT' },
        [pscustomobject]@{ shot = $shotsById['P01']; candidate = 2; stage = 'IPA' }
    )
    if ([bool]$config.identity.faceid_enabled) { $jobs += [pscustomobject]@{ shot = $shotsById['P01']; candidate = 3; stage = 'FID' } }
    $jobs += [pscustomobject]@{ shot = $shotsById['M01']; candidate = 1; stage = 'IPA' }
    $jobs += [pscustomobject]@{ shot = $shotsById['C01']; candidate = 1; stage = 'IPA' }
}
elseif ($Mode -eq 'CompositionPilot') {
    $jobs = @(
        [pscustomobject]@{ shot = $shotsById['P01']; candidate = 9; stage = 'POSE' },
        [pscustomobject]@{ shot = $shotsById['M01']; candidate = 4; stage = 'POSE' },
        [pscustomobject]@{ shot = $shotsById['C01']; candidate = 3; stage = 'TXT' }
    )
}
else {
    $selectedIds = if ($ShotIds.Count -gt 0) { @($ShotIds) } else { @($config.shots.id) }
    $jobs = foreach ($id in $selectedIds) {
        if (-not $shotsById.ContainsKey($id)) { throw "Unknown shot id: $id" }
        foreach ($candidate in $CandidateStart..$CandidateEnd) { [pscustomobject]@{ shot = $shotsById[$id]; candidate = $candidate; stage = $Conditioning } }
    }
}

Write-Host "V4 mode: $Mode | jobs: $($jobs.Count) | output: $outputRoot"
if ($ValidateOnly) {
    $jobs | ForEach-Object { Write-Host ("{0} C{1:00} {2} {3}x{4}" -f $_.shot.id, $_.candidate, $_.stage, $_.shot.width, $_.shot.height) }
    Write-Host 'Validation completed without submitting generation requests.'
    return
}
foreach ($job in $jobs) { Invoke-Job -Shot $job.shot -Candidate $job.candidate -Stage $job.stage }
Write-Gallery
Write-Host "Manifest: $manifestPath"
Write-Host "Gallery: $(Join-Path $outputRoot 'report.html')"
