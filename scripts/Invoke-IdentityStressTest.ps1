[CmdletBinding()]
param(
    [string]$ApiBaseUri = 'http://127.0.0.1:7860',
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\identity-stress-test-v1.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\runs\identity-stress-test-v1'),
    [ValidateSet('TXT', 'IPA', 'FID', 'POS', 'FIN')]
    [string[]]$Stages = @('TXT', 'IPA', 'FID', 'POS', 'FIN'),
    [ValidateRange(1, 10)]
    [int]$StartShot = 1,
    [ValidateRange(1, 10)]
    [int]$EndShot = 10,
    [ValidateRange(60, 7200)]
    [int]$TimeoutSec = 1800,
    [string]$PackagePath = 'D:\AIMODEL\StabilityMatrix-win-x64\Data\Packages\SD.Next',
    [string]$AnalysisRoot = 'D:\AIMODEL\StabilityMatrix-win-x64\Data\Models\Diffusers\models--vladmandic--insightface-faceanalysis',
    [string]$SwapperModel = 'D:\AIMODEL\StabilityMatrix-win-x64\Data\Packages\SD.Next\models\huggingface\models--ezioruan--inswapper_128.onnx\snapshots\6ffdf0e83c5996cc425e77b59913fc48d79441be\inswapper_128.onnx',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing.Common
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$config = Get-Content -LiteralPath (Resolve-Path -LiteralPath $ConfigPath).Path -Raw | ConvertFrom-Json
$baseUri = $ApiBaseUri.TrimEnd('/')
$txt2imgUri = "$baseUri/sdapi/v1/txt2img"
$controlUri = "$baseUri/sdapi/v1/control"
$preprocessUri = "$baseUri/sdapi/v1/preprocess"
$detailUri = "$baseUri/sdapi/v1/detail"
$processUri = "$baseUri/sdapi/v1/extra-single-image"
$invariant = [Globalization.CultureInfo]::InvariantCulture

if ($StartShot -gt $EndShot) {
    throw 'StartShot must be less than or equal to EndShot.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$requestDirectory = Join-Path $OutputDirectory 'requests'
$poseDirectory = Join-Path $OutputDirectory 'pose-maps'
$detailDirectory = Join-Path $OutputDirectory 'detailer-intermediates'
$responseDirectory = Join-Path $OutputDirectory 'response-info'
New-Item -ItemType Directory -Path $requestDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $poseDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $detailDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $responseDirectory -Force | Out-Null

$referencePath = Join-Path $repoRoot ([string]$config.subject.reference_image)
$referencePath = (Resolve-Path -LiteralPath $referencePath).Path
$referenceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $referencePath).Hash
if ($referenceHash -ine [string]$config.subject.reference_sha256) {
    throw "Reference hash mismatch. Expected $($config.subject.reference_sha256), found $referenceHash."
}
$referenceBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($referencePath))
$faceSwapReferencePath = Join-Path $repoRoot ([string]$config.identity.face_swap_reference)
$faceSwapReferencePath = (Resolve-Path -LiteralPath $faceSwapReferencePath).Path
$faceSwapReferenceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $faceSwapReferencePath).Hash
if ($faceSwapReferenceHash -ine [string]$config.identity.face_swap_reference_sha256) {
    throw "FaceSwap reference hash mismatch. Expected $($config.identity.face_swap_reference_sha256), found $faceSwapReferenceHash."
}

$manifestPath = Join-Path $OutputDirectory 'manifest.csv'
$script:records = if (Test-Path -LiteralPath $manifestPath) { @(Import-Csv -LiteralPath $manifestPath) } else { @() }

function Save-Base64Image {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Encoded,
        [Parameter(Mandatory)]
        [string]$Path
    )

    $clean = $Encoded -replace '^data:image/[^;]+;base64,', ''
    $bytes = [Convert]::FromBase64String($clean)
    $stream = [IO.MemoryStream]::new($bytes, $false)
    $source = $null
    $bitmap = $null
    try {
        $source = [Drawing.Image]::FromStream($stream)
        $bitmap = [Drawing.Bitmap]::new($source)
        $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        if ($null -ne $bitmap) { $bitmap.Dispose() }
        if ($null -ne $source) { $source.Dispose() }
        $stream.Dispose()
    }
}

function Get-FileBase64 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path))
}

function Get-ImageDimensions {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    $image = $null
    try {
        $image = [Drawing.Image]::FromStream($stream)
        return [pscustomobject]@{
            Width = $image.Width
            Height = $image.Height
        }
    }
    finally {
        if ($null -ne $image) { $image.Dispose() }
        $stream.Dispose()
    }
}

function Get-ImageContentMetrics {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $stream = [IO.File]::OpenRead($Path)
    $source = $null
    $bitmap = $null
    try {
        $source = [Drawing.Image]::FromStream($stream)
        $bitmap = [Drawing.Bitmap]::new($source)
        $strideX = [Math]::Max(1, [int][Math]::Floor($bitmap.Width / 64))
        $strideY = [Math]::Max(1, [int][Math]::Floor($bitmap.Height / 64))
        $colors = [Collections.Generic.HashSet[int]]::new()
        [long]$rgbSum = 0
        [long]$sampleCount = 0
        $minLuminance = 255
        $maxLuminance = 0

        for ($y = 0; $y -lt $bitmap.Height; $y += $strideY) {
            for ($x = 0; $x -lt $bitmap.Width; $x += $strideX) {
                $pixel = $bitmap.GetPixel($x, $y)
                [void]$colors.Add($pixel.ToArgb())
                $luminance = [int](($pixel.R + $pixel.G + $pixel.B) / 3)
                $rgbSum += $pixel.R + $pixel.G + $pixel.B
                $sampleCount++
                if ($luminance -lt $minLuminance) { $minLuminance = $luminance }
                if ($luminance -gt $maxLuminance) { $maxLuminance = $luminance }
            }
        }

        return [pscustomobject]@{
            Width = $bitmap.Width
            Height = $bitmap.Height
            SampleCount = $sampleCount
            UniqueColors = $colors.Count
            RgbSum = $rgbSum
            LuminanceMin = $minLuminance
            LuminanceMax = $maxLuminance
            LuminanceRange = $maxLuminance - $minLuminance
        }
    }
    finally {
        if ($null -ne $bitmap) { $bitmap.Dispose() }
        if ($null -ne $source) { $source.Dispose() }
        $stream.Dispose()
    }
}

function Assert-UsableImage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $metrics = Get-ImageContentMetrics -Path $Path
    if ($metrics.UniqueColors -lt 16 -or $metrics.LuminanceRange -lt 8 -or $metrics.RgbSum -eq 0) {
        throw "Generated image is blank or nearly uniform: $Path (sample_colors=$($metrics.UniqueColors), luminance_range=$($metrics.LuminanceRange), rgb_sum=$($metrics.RgbSum))."
    }
    return $metrics
}

function Test-ExistingStageOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][int]$ExpectedWidth,
        [Parameter(Mandatory)][int]$ExpectedHeight
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }
    try {
        $metrics = Assert-UsableImage -Path $Path
        if ($metrics.Width -eq $ExpectedWidth -and $metrics.Height -eq $ExpectedHeight) {
            return $true
        }
        Write-Warning "Existing PNG has unexpected dimensions and will be regenerated: $Path ($($metrics.Width)x$($metrics.Height), expected ${ExpectedWidth}x${ExpectedHeight})."
    }
    catch {
        Write-Warning "Existing output is not a readable PNG and will be regenerated: $Path"
    }
    return $false
}

function Write-ResponseInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Response
    )

    $fileName = "$Name.json"
    $record = [ordered]@{
        stage = $Name
        generated_at = (Get-Date).ToString('o')
        info = [string]$Response.info
        html_info = [string]$Response.html_info
    }
    $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $responseDirectory $fileName) -Encoding utf8
    return $fileName
}

function Write-RequestSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][object]$Payload
    )
    $path = Join-Path $requestDirectory "$Name.json"
    $Payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
}

function Set-ManifestRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Shot,
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][long]$Seed,
        [Parameter(Mandatory)][string]$File,
        [Parameter(Mandatory)][string]$Status,
        [double]$ElapsedSeconds = 0,
        [string]$Conditioning = '',
        [string]$ErrorMessage = '',
        [string]$ParentFile = '',
        [string]$ResponseInfoFile = ''
    )

    $prior = @($script:records | Where-Object { $_.shot -eq $Shot -and $_.stage -eq $Stage }) | Select-Object -First 1
    if ($Status -eq 'existing' -and $null -ne $prior -and $prior.status -in @('ok', 'existing')) {
        return
    }

    $outputPath = Join-Path $OutputDirectory $File
    $outputHash = ''
    $outputWidth = 0
    $outputHeight = 0
    if (Test-Path -LiteralPath $outputPath) {
        $dimensions = Get-ImageDimensions -Path $outputPath
        $outputHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $outputPath).Hash
        $outputWidth = $dimensions.Width
        $outputHeight = $dimensions.Height
    }
    $parentHash = ''
    if ($ParentFile) {
        $parentPath = Join-Path $OutputDirectory $ParentFile
        if (Test-Path -LiteralPath $parentPath) {
            $parentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $parentPath).Hash
        }
    }

    $script:records = @($script:records | Where-Object { -not ($_.shot -eq $Shot -and $_.stage -eq $Stage) })
    $script:records += [pscustomobject][ordered]@{
        shot = $Shot
        stage = $Stage
        seed = $Seed
        file = $File
        status = $Status
        conditioning = $Conditioning
        elapsed_seconds = $ElapsedSeconds.ToString('0.0', $invariant)
        checkpoint = [string]$config.model.checkpoint
        sampler = [string]$config.model.sampler
        scheduler = [string]$config.model.scheduler
        cfg = ([double]$config.model.cfg).ToString('0.0', $invariant)
        steps = [int]$config.model.steps
        width = [int]$config.model.width
        height = [int]$config.model.height
        actual_width = $outputWidth
        actual_height = $outputHeight
        output_sha256 = $outputHash
        parent_file = $ParentFile
        parent_sha256 = $parentHash
        response_info_file = $ResponseInfoFile
        sdnext_revision = [string]$config.tested_runtime.sdnext_revision
        error = $ErrorMessage
        updated_at = (Get-Date).ToString('o')
    }
    $script:records |
        Sort-Object shot, @{ Expression = { @('TXT', 'IPA', 'FID', 'POS', 'FIN').IndexOf($_.stage) } } |
        Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding utf8
}

function Wait-SDNextIdle {
    [CmdletBinding()]
    param([int]$MaxWaitSeconds = 7200)

    $deadline = (Get-Date).AddSeconds($MaxWaitSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $progress = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/progress?skip_current_image=true" -Method Get -TimeoutSec 15
            $activeSteps = [int]$progress.state.sampling_steps
            $activeProgress = [double]$progress.progress
            if ($activeSteps -eq 0 -and $activeProgress -eq 0) {
                return
            }
            Write-Host ("Waiting for SD.Next queue: {0:P0}, step {1}/{2}" -f $activeProgress, $progress.state.sampling_step, $activeSteps)
        }
        catch {
            throw "SD.Next became unreachable while waiting for its queue: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds 10
    }
    throw "SD.Next did not become idle within $MaxWaitSeconds seconds."
}

function Invoke-SDNextPost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][object]$Payload,
        [Parameter(Mandatory)][string]$RequestName
    )

    Write-RequestSnapshot -Name $RequestName -Payload $Payload
    Wait-SDNextIdle
    return Invoke-RestMethod -Uri $Uri -Method Post -ContentType 'application/json' -Body ($Payload | ConvertTo-Json -Depth 20) -TimeoutSec $TimeoutSec
}

function New-BasePayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][long]$Seed
    )

    return [ordered]@{
        prompt = $Prompt
        negative_prompt = [string]$config.negative_prompt
        seed = $Seed
        batch_size = 1
        n_iter = 1
        steps = [int]$config.model.steps
        width = [int]$config.model.width
        height = [int]$config.model.height
        sampler_name = [string]$config.model.sampler
        schedulers_sigma = [string]$config.model.scheduler
        cfg_scale = [double]$config.model.cfg
        guidance_scale = [double]$config.model.cfg
        vae_type = [string]$config.model.vae
        detailer_enabled = $false
        enable_hr = $false
        save_images = $false
        send_images = $true
        do_not_save_samples = $true
    }
}

function New-IPAdapterUnit {
    return [ordered]@{
        adapter = [string]$config.identity.ip_adapter
        images = @($referenceBase64)
        masks = @()
        scale = [double]$config.identity.ip_scale
        start = [double]$config.identity.ip_start
        end = [double]$config.identity.ip_end
        crop = [bool]$config.identity.ip_crop
    }
}

function Save-GenerationResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Response,
        [Parameter(Mandatory)][string]$OutputPath
    )
    if (-not $Response.images -or $Response.images.Count -lt 1) {
        throw 'The SD.Next response did not contain an image.'
    }
    Save-Base64Image -Encoded ([string]$Response.images[0]) -Path $OutputPath
    Assert-UsableImage -Path $OutputPath | Out-Null
}

function Invoke-TxtStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Shot,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][ValidateSet('TXT', 'IPA', 'FID')][string]$Stage
    )

    $fileName = "$($Shot.id)-$Stage.png"
    $filePath = Join-Path $OutputDirectory $fileName
    if ((Test-ExistingStageOutput -Path $filePath -ExpectedWidth ([int]$config.model.width) -ExpectedHeight ([int]$config.model.height)) -and -not $Force) {
        Write-Host "[$($Shot.id)-$Stage] Existing output; skipping."
        Set-ManifestRecord -Shot $Shot.id -Stage $Stage -Seed $Shot.seed -File $fileName -Status 'existing' -Conditioning $Stage
        return $filePath
    }

    $payload = New-BasePayload -Prompt $Prompt -Seed ([long]$Shot.seed)
    $conditioning = 'text-only'
    if ($Stage -eq 'IPA') {
        $payload.ip_adapter = @(New-IPAdapterUnit)
        $conditioning = "IP-Adapter $($config.identity.ip_adapter) scale=$($config.identity.ip_scale)"
    }
    elseif ($Stage -eq 'FID') {
        $payload.script_name = 'Face: Multiple ID Transfers'
        $payload.script_args = @(
            'FaceID',
            @($referenceBase64),
            'ReSwapper 256 0.2',
            $false,
            [string]$config.identity.faceid_model,
            $false,
            $true,
            [double]$config.identity.faceid_strength,
            [double]$config.identity.faceid_structure,
            1.0,
            0.5,
            $true,
            'PhotoMaker v2',
            'person',
            1.0,
            0.5,
            $true
        )
        $conditioning = "FaceID $($config.identity.faceid_model) strength=$($config.identity.faceid_strength)"
    }

    $started = Get-Date
    try {
        Write-Host "[$($Shot.id)-$Stage] Generating..."
        $response = Invoke-SDNextPost -Uri $txt2imgUri -Payload $payload -RequestName "$($Shot.id)-$Stage"
        Save-GenerationResponse -Response $response -OutputPath $filePath
        $responseInfoFile = Write-ResponseInfo -Name "$($Shot.id)-$Stage" -Response $response
        $elapsed = ((Get-Date) - $started).TotalSeconds
        Set-ManifestRecord -Shot $Shot.id -Stage $Stage -Seed $Shot.seed -File $fileName -Status 'ok' -ElapsedSeconds $elapsed -Conditioning $conditioning -ResponseInfoFile $responseInfoFile
        return $filePath
    }
    catch {
        $elapsed = ((Get-Date) - $started).TotalSeconds
        Set-ManifestRecord -Shot $Shot.id -Stage $Stage -Seed $Shot.seed -File $fileName -Status 'failed' -ElapsedSeconds $elapsed -Conditioning $conditioning -ErrorMessage $_.Exception.Message
        Write-Warning "[$($Shot.id)-$Stage] Failed: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-PoseStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Shot,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$PoseSourcePath
    )

    $stage = 'POS'
    $fileName = "$($Shot.id)-$stage.png"
    $filePath = Join-Path $OutputDirectory $fileName
    if ((Test-ExistingStageOutput -Path $filePath -ExpectedWidth ([int]$config.model.width) -ExpectedHeight ([int]$config.model.height)) -and -not $Force) {
        Write-Host "[$($Shot.id)-$stage] Existing output; skipping."
        Set-ManifestRecord -Shot $Shot.id -Stage $stage -Seed $Shot.seed -File $fileName -Status 'existing' -Conditioning 'OpenPose only; identity deferred to FIN'
        return $filePath
    }

    $started = Get-Date
    try {
        $sourceBase64 = Get-FileBase64 -Path $PoseSourcePath
        $poseMapPath = Join-Path $poseDirectory "$($Shot.id)-openpose.png"
        if ((Test-Path -LiteralPath $poseMapPath) -and -not $Force) {
            $poseBase64 = Get-FileBase64 -Path $poseMapPath
        }
        else {
            Write-Host "[$($Shot.id)-POS] Extracting OpenPose map..."
            $preprocessPayload = [ordered]@{
                image = $sourceBase64
                model = [string]$config.identity.openpose_preprocessor
                params = [ordered]@{
                    include_body = $true
                    include_hand = $true
                    include_face = $false
                }
            }
            $preprocessResponse = Invoke-SDNextPost -Uri $preprocessUri -Payload $preprocessPayload -RequestName "$($Shot.id)-PRE"
            if (-not $preprocessResponse.image) {
                throw 'OpenPose preprocessing returned no map.'
            }
            Save-Base64Image -Encoded ([string]$preprocessResponse.image) -Path $poseMapPath
            $poseBase64 = Get-FileBase64 -Path $poseMapPath
        }

        $controlUnit = [ordered]@{
            process = [string]$config.identity.openpose_preprocessor
            model = [string]$config.identity.openpose_model
            strength = [double]$config.identity.openpose_strength
            start = [double]$config.identity.openpose_start
            end = [double]$config.identity.openpose_end
            unit_type = 'controlnet'
            process_params = [ordered]@{
                include_body = $true
                include_hand = $true
                include_face = $false
            }
            override = $poseBase64
        }

        $payload = [ordered]@{
            input_type = 0
            prompt = $Prompt
            negative_prompt = [string]$config.negative_prompt
            steps = [int]$config.model.steps
            sampler_name = [string]$config.model.sampler
            schedulers_sigma = [string]$config.model.scheduler
            seed = [long]$Shot.seed
            guidance_scale = [double]$config.model.cfg
            cfg_scale = [double]$config.model.cfg
            vae_type = [string]$config.model.vae
            width_before = [int]$config.model.width
            height_before = [int]$config.model.height
            batch_count = 1
            batch_size = 1
            save_images = $false
            send_images = $true
            unit_type = 'controlnet'
            inputs = @()
            control = @($controlUnit)
        }

        Write-Host "[$($Shot.id)-POS] Generating the pose-correct base with OpenPose only..."
        $response = Invoke-SDNextPost -Uri $controlUri -Payload $payload -RequestName "$($Shot.id)-POS"
        Save-GenerationResponse -Response $response -OutputPath $filePath
        $responseInfoFile = Write-ResponseInfo -Name "$($Shot.id)-POS" -Response $response
        $elapsed = ((Get-Date) - $started).TotalSeconds
        Set-ManifestRecord -Shot $Shot.id -Stage $stage -Seed $Shot.seed -File $fileName -Status 'ok' -ElapsedSeconds $elapsed -Conditioning 'OpenPose only; identity deferred to FIN' -ParentFile ([IO.Path]::GetFileName($PoseSourcePath)) -ResponseInfoFile $responseInfoFile
        return $filePath
    }
    catch {
        $elapsed = ((Get-Date) - $started).TotalSeconds
        Set-ManifestRecord -Shot $Shot.id -Stage $stage -Seed $Shot.seed -File $fileName -Status 'failed' -ElapsedSeconds $elapsed -Conditioning 'OpenPose only; identity deferred to FIN' -ErrorMessage $_.Exception.Message
        Write-Warning "[$($Shot.id)-POS] Failed: $($_.Exception.Message)"
        return $null
    }
}

function Invoke-FinishStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Shot,
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string]$SourcePath
    )

    $stage = 'FIN'
    $fileName = "$($Shot.id)-$stage.png"
    $filePath = Join-Path $OutputDirectory $fileName
    if ((Test-ExistingStageOutput -Path $filePath -ExpectedWidth (2 * [int]$config.model.width) -ExpectedHeight (2 * [int]$config.model.height)) -and -not $Force) {
        Write-Host "[$($Shot.id)-$stage] Existing output; skipping."
        Set-ManifestRecord -Shot $Shot.id -Stage $stage -Seed $Shot.seed -File $fileName -Status 'existing' -Conditioning 'face detailer + 2x RealESRGAN Compact + offline FaceSwap'
        return $filePath
    }

    $started = Get-Date
    try {
        $sourceBase64 = Get-FileBase64 -Path $SourcePath
        $detailPayload = [ordered]@{
            image = $sourceBase64
            seed = [long]$Shot.seed
            detailer_models = @('face-yolo8n')
            detailer_prompt = $Prompt
            detailer_negative = [string]$config.negative_prompt
            detailer_steps = 10
            detailer_strength = 0.25
            detailer_resolution = 768
            detailer_sampler = [string]$config.model.sampler
            detailer_cfg_scale = [double]$config.model.cfg
            detailer_classes = 'face'
            detailer_conf = 0.3
            detailer_max = 1
            detailer_blur = 8
            detailer_padding = 16
        }
        Write-Host "[$($Shot.id)-FIN] Running conservative face detailer..."
        $detailResponse = Invoke-SDNextPost -Uri $detailUri -Payload $detailPayload -RequestName "$($Shot.id)-DET"
        if (-not $detailResponse.image) {
            throw 'Detailer returned no image.'
        }
        $detailPath = Join-Path $detailDirectory "$($Shot.id)-DET.png"
        Save-Base64Image -Encoded ([string]$detailResponse.image) -Path $detailPath
        Assert-UsableImage -Path $detailPath | Out-Null

        $upscalePayload = [ordered]@{
            image = Get-FileBase64 -Path $detailPath
            resize_mode = 0
            show_extras_results = $true
            upscaling_resize = 2
            upscaling_crop = $false
            upscaler_1 = 'Spandrel 2x RealESRGAN Compact'
            upscaler_2 = 'None'
            extras_upscaler_2_visibility = 0
        }
        Write-Host "[$($Shot.id)-FIN] Upscaling 2x..."
        $upscaleResponse = Invoke-SDNextPost -Uri $processUri -Payload $upscalePayload -RequestName "$($Shot.id)-FIN"
        if (-not $upscaleResponse.image) {
            throw 'Upscaler returned no image.'
        }
        $upscaledPath = Join-Path $detailDirectory "$($Shot.id)-UP-2X.png"
        Save-Base64Image -Encoded ([string]$upscaleResponse.image) -Path $upscaledPath
        Assert-UsableImage -Path $upscaledPath | Out-Null

        Write-Host "[$($Shot.id)-FIN] Applying identity after pose, detail, and upscale..."
        $python = Join-Path $PackagePath 'venv\Scripts\python.exe'
        $faceSwapScript = Join-Path $PSScriptRoot 'Invoke-OfflineFaceSwap.py'
        & $python $faceSwapScript --source $faceSwapReferencePath --target $upscaledPath --output $filePath --analysis-root $AnalysisRoot --swapper-model $SwapperModel
        if ($LASTEXITCODE -ne 0) {
            throw "Offline FaceSwap failed with exit code $LASTEXITCODE."
        }
        Assert-UsableImage -Path $filePath | Out-Null
        $responseInfoFile = Write-ResponseInfo -Name "$($Shot.id)-FIN" -Response $upscaleResponse
        $elapsed = ((Get-Date) - $started).TotalSeconds
        Set-ManifestRecord -Shot $Shot.id -Stage $stage -Seed $Shot.seed -File $fileName -Status 'ok' -ElapsedSeconds $elapsed -Conditioning 'face-yolo8n detailer + Spandrel 2x RealESRGAN Compact + offline FaceSwap' -ParentFile ([IO.Path]::GetFileName($SourcePath)) -ResponseInfoFile $responseInfoFile
        return $filePath
    }
    catch {
        $elapsed = ((Get-Date) - $started).TotalSeconds
        Set-ManifestRecord -Shot $Shot.id -Stage $stage -Seed $Shot.seed -File $fileName -Status 'failed' -ElapsedSeconds $elapsed -Conditioning 'face-yolo8n detailer + Spandrel 2x RealESRGAN Compact + offline FaceSwap' -ErrorMessage $_.Exception.Message
        Write-Warning "[$($Shot.id)-FIN] Failed: $($_.Exception.Message)"
        return $null
    }
}

function Write-HtmlReport {
    $rows = foreach ($shot in $config.shots) {
        $cells = foreach ($stage in @('TXT', 'IPA', 'FID', 'POS', 'FIN')) {
            $name = "$($shot.id)-$stage.png"
            $path = Join-Path $OutputDirectory $name
            if (Test-Path -LiteralPath $path) {
                "<td><a href='$name'><img src='$name' alt='$($shot.id)-$stage'></a><div>$stage</div></td>"
            }
            else {
                "<td class='missing'><div>$stage<br>missing</div></td>"
            }
        }
        "<tr><th>$($shot.id)<small>$($shot.scene)<br>$($shot.outfit)<br>$($shot.pose)</small></th>$($cells -join '')</tr>"
    }

    $html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Identity stress test v1</title>
<style>
body{font-family:Arial,sans-serif;background:#171717;color:#eee;margin:20px}table{border-collapse:collapse;width:100%}th,td{border:1px solid #444;padding:8px;text-align:center;vertical-align:top}th{width:230px;text-align:left}small{display:block;font-weight:normal;color:#bbb;margin-top:6px;line-height:1.35}img{width:180px;height:270px;object-fit:contain;background:#000}.missing{color:#888;background:#222}a{color:#8fd3ff}
</style>
</head>
<body>
<h1>Identity stress test v1</h1>
<p>TXT = text only; IPA = IP-Adapter Plus Face; FID = FaceID; POS = OpenPose-only composition; FIN = POS + conservative face detailer + 2x upscale + offline FaceSwap.</p>
<table><thead><tr><th>Shot</th><th>TXT</th><th>IPA</th><th>FID</th><th>POS</th><th>FIN</th></tr></thead><tbody>
$($rows -join "`n")
</tbody></table>
</body>
</html>
"@
    $html | Set-Content -LiteralPath (Join-Path $OutputDirectory 'report.html') -Encoding utf8
}

function Write-EvaluationTemplate {
    $evaluationPath = Join-Path $OutputDirectory 'evaluation.csv'
    if (Test-Path -LiteralPath $evaluationPath) {
        return
    }
    $rows = foreach ($shot in $config.shots) {
        foreach ($stage in @('TXT', 'IPA', 'FID', 'POS', 'FIN')) {
            [pscustomobject][ordered]@{
                shot = $shot.id
                stage = $stage
                identity_continuity_1_to_5 = ''
                full_body_framing_1_to_5 = ''
                anatomy_1_to_5 = ''
                pose_compliance_1_to_5 = ''
                wardrobe_compliance_1_to_5 = ''
                scene_compliance_1_to_5 = ''
                realism_1_to_5 = ''
                expression_1_to_5 = ''
                selected = ''
                notes = ''
            }
        }
    }
    $rows | Export-Csv -LiteralPath $evaluationPath -NoTypeInformation -Encoding utf8
}

Write-Host 'Preflight: checking SD.Next...'
try {
    $options = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/options" -Method Get -TimeoutSec 30
}
catch {
    throw "SD.Next is not reachable at $baseUri. Start it and make sure the checkpoint is loaded. Error: $($_.Exception.Message)"
}
if ([string]$options.sd_model_checkpoint -notlike "*$($config.model.autov2)*") {
    throw "Wrong checkpoint selected. Expected AutoV2 $($config.model.autov2); SD.Next reports '$($options.sd_model_checkpoint)'."
}
$checkpoint = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/checkpoint" -Method Get -TimeoutSec 30
if (-not $checkpoint.class) {
    throw 'The checkpoint is selected but not loaded. Wait for SD.Next model loading to finish, then retry.'
}
if ([string]$checkpoint.hash -notlike "*$($config.model.autov2)*" -and [string]$checkpoint.title -notlike "*$($config.model.autov2)*") {
    throw "The loaded checkpoint does not match AutoV2 $($config.model.autov2). Loaded: '$($checkpoint.title)' hash '$($checkpoint.hash)'."
}

if ($Stages -contains 'POS') {
    $preprocessors = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/preprocessors" -Method Get -TimeoutSec 30
    if ('OpenPose' -notin @($preprocessors.name)) {
        throw 'Required preprocessor is unavailable: OpenPose.'
    }
    $controlModelsResponse = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/control-models" -Method Get -TimeoutSec 30
    $controlModels = @($controlModelsResponse)
    if ([string]$config.identity.openpose_model -notin $controlModels) {
        throw "Required ControlNet model is unavailable: $($config.identity.openpose_model)."
    }
}
if ($Stages -contains 'IPA') {
    $ipAdaptersResponse = Invoke-RestMethod -Uri "$baseUri/sdapi/v1/ip-adapters" -Method Get -TimeoutSec 30
    $ipAdapters = @($ipAdaptersResponse)
    if ([string]$config.identity.ip_adapter -notin $ipAdapters) {
        throw "Required IP-Adapter is unavailable: $($config.identity.ip_adapter)."
    }
}
if ($Stages -contains 'FIN') {
    $detailers = @(Invoke-RestMethod -Uri "$baseUri/sdapi/v1/detailers" -Method Get -TimeoutSec 30)
    if ('face-yolo8n' -notin @($detailers.name)) {
        throw 'Required detailer is unavailable: face-yolo8n.'
    }
    $upscalers = @(Invoke-RestMethod -Uri "$baseUri/sdapi/v1/upscalers" -Method Get -TimeoutSec 30)
    if ('Spandrel 2x RealESRGAN Compact' -notin @($upscalers.name)) {
        throw 'Required upscaler is unavailable: Spandrel 2x RealESRGAN Compact.'
    }
    foreach ($requiredPath in @(
        (Join-Path $PackagePath 'venv\Scripts\python.exe'),
        (Join-Path $PSScriptRoot 'Invoke-OfflineFaceSwap.py'),
        (Join-Path $AnalysisRoot 'models\buffalo_l'),
        $SwapperModel
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required offline FaceSwap dependency is unavailable: $requiredPath"
        }
    }
}

$selectedShots = @($config.shots | Where-Object {
    $number = [int]($_.id -replace '^S', '')
    $number -ge $StartShot -and $number -le $EndShot
})

Write-Host "Experiment: $($config.experiment)"
Write-Host "Shots: $StartShot through $EndShot"
Write-Host "Stages: $($Stages -join ', ')"
Write-Host "Reference: $referencePath"
Write-Host 'Do not use the SD.Next WebUI while this script is running.'
Write-Host ''
Write-EvaluationTemplate

$orderedStages = @('TXT', 'IPA', 'FID', 'POS', 'FIN') | Where-Object { $Stages -contains $_ }
foreach ($stage in $orderedStages) {
    Write-Host "===== Stage $stage ====="
    foreach ($shot in $selectedShots) {
        $prompt = "$($config.realism_prompt), $($config.identity.prompt), $($config.sensuality_prompt), wearing $($shot.outfit), $($shot.pose), $($shot.expression), $($shot.scene)"
        Write-Host "--- $($shot.id): $($shot.scene)"

        switch ($stage) {
            'TXT' {
                [void](Invoke-TxtStage -Shot $shot -Prompt $prompt -Stage 'TXT')
            }
            'IPA' {
                [void](Invoke-TxtStage -Shot $shot -Prompt $prompt -Stage 'IPA')
            }
            'FID' {
                [void](Invoke-TxtStage -Shot $shot -Prompt $prompt -Stage 'FID')
            }
            'POS' {
                $txtPath = Join-Path $OutputDirectory "$($shot.id)-TXT.png"
                if (Test-ExistingStageOutput -Path $txtPath -ExpectedWidth ([int]$config.model.width) -ExpectedHeight ([int]$config.model.height)) {
                    [void](Invoke-PoseStage -Shot $shot -Prompt $prompt -PoseSourcePath $txtPath)
                }
                else {
                    Set-ManifestRecord -Shot $shot.id -Stage 'POS' -Seed $shot.seed -File "$($shot.id)-POS.png" -Status 'blocked' -Conditioning 'OpenPose only; identity deferred to FIN' -ErrorMessage 'A valid TXT pose source is missing.'
                }
            }
            'FIN' {
                $posePath = Join-Path $OutputDirectory "$($shot.id)-POS.png"
                if (Test-ExistingStageOutput -Path $posePath -ExpectedWidth ([int]$config.model.width) -ExpectedHeight ([int]$config.model.height)) {
                    [void](Invoke-FinishStage -Shot $shot -Prompt $prompt -SourcePath $posePath)
                }
                else {
                    Set-ManifestRecord -Shot $shot.id -Stage 'FIN' -Seed $shot.seed -File "$($shot.id)-FIN.png" -Status 'blocked' -Conditioning 'face detailer + 2x upscale + offline FaceSwap' -ErrorMessage 'A valid POS source is missing.'
                }
            }
        }
        Write-HtmlReport
    }
    Write-Host ''
}

Write-HtmlReport
$ok = @($script:records | Where-Object { $_.status -in @('ok', 'existing') }).Count
$failed = @($script:records | Where-Object { $_.status -eq 'failed' }).Count
$blocked = @($script:records | Where-Object { $_.status -eq 'blocked' }).Count
Write-Host "Complete outputs: $ok; failed: $failed; blocked: $blocked"
Write-Host "Manifest: $manifestPath"
Write-Host "Visual report: $(Join-Path $OutputDirectory 'report.html')"
Write-Host "Evaluation sheet: $(Join-Path $OutputDirectory 'evaluation.csv')"
