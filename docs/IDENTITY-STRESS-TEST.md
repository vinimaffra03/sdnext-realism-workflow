# Camila Identity Stress Test

This experiment produces a controlled 50-image comparison for Camila, a fictional and clearly adult 23-year-old character. It tests ten full-body scenes across five conditioning and finishing stages while keeping the prompt, checkpoint, seed, sampler, schedule, CFG, step count, and canvas size fixed within each scene.

The purpose is to measure what each module actually contributes. It is not a claim that every module improves every image.

## Safety and provenance

- Camila is fictional and clearly adult.
- The wardrobe is opaque and the scenes are non-explicit fashion, lifestyle, and swimwear photography.
- The identity reference was generated specifically for this workflow and was not sourced from a real-person social-media account.
- The script verifies the identity-reference SHA-256 before sending it to SD.Next.
- Do not replace the reference with a real person's likeness unless documented consent and usage rights are available.

Reference used by this version:

```text
samples/camila-reference-seed-231984751.png
SHA-256: 00933EC3A8669F4C64A3CD9739782C4714E5383A4C5702E3E5B783D49CBC76DC
```

## Controlled matrix

Each row is one scene. Each column changes the conditioning or finishing stage.

| Stage | Meaning | Input and purpose |
|---|---|---|
| `TXT` | Text-only baseline | Prompt and fixed seed only. Establishes the unconditioned pose and identity baseline. |
| `IPA` | IP-Adapter Plus Face | Adds the authorized Camila reference at a conservative scale of `0.45`. Measures general facial resemblance. |
| `FID` | FaceID | Uses the same reference with FaceID Base at strength `0.8`. The Base implementation ignores the required compatibility argument named `structure`. Measures identity transfer independently from IP-Adapter. |
| `POS` | OpenPose composition | Extracts a pose map from the matching `TXT` image and generates the pose-correct base without IP-Adapter. Identity is intentionally deferred so it cannot override body composition. |
| `FIN` | Two-stage finished candidate | Runs a conservative face detailer on `POS`, applies a 2x RealESRGAN Compact upscale, then transfers the authorized fictional identity with offline InsightFace InSwapper. |

Ten concepts multiplied by five variants yields 50 comparison files. The ten rows vary setting, wardrobe, stance, movement, camera relationship, and facial expression. This is not 50 unique compositions: every concept intentionally has five related variants. Exact values live in [`config/identity-stress-test-v1.json`](../config/identity-stress-test-v1.json).

Within one row, do not compare results after changing the seed or prompt. That would confound the module comparison.

## Fixed generation settings

| Setting | Value |
|---|---|
| Checkpoint | CyberRealistic V9 FP16 |
| AutoV2 | `22C7896047` |
| Sampler | DPM++ SDE |
| Sigma schedule | Karras |
| CFG | 6.0 |
| Steps | 25 |
| Canvas | 512 x 768 |
| VAE | Full |
| Batch | 1 |
| Hires fix | Disabled |

Tested SD.Next revision: `684940e015911efab2911667231946d91fef9f50`, diffusers backend.

The vertical 512 x 768 canvas is intentionally conservative for a 4 GB GPU. The final stage upscales an approved 512 x 768 result rather than running the diffusion model at a larger native resolution.

## Prerequisites

1. Install Stability Matrix.
2. Install the SD.Next package through Stability Matrix.
3. Install the exact CyberRealistic V9 FP16 checkpoint documented in the main README.
4. Apply the tested API compatibility patch described below if the `POS` stage will be used.
5. Start SD.Next and wait until the checkpoint has fully loaded at `http://127.0.0.1:7860`.
6. Allow the first use of IP-Adapter, FaceID, OpenPose, the detailer, RealESRGAN, InsightFace Buffalo-L, and InSwapper to download their required auxiliary models.

The first conditioned image can take substantially longer than later images because SD.Next may download and initialize CLIP vision, IP-Adapter, InsightFace, ControlNet, detector, or upscaler assets. Keep the network available for that first run.

For a 16 GB system, close unused memory-intensive applications before loading the checkpoint. Do not use the WebUI to start another generation while the batch script owns the API queue.

If ordinary Stability Matrix startup fails with Windows error 1455 or a Python `MemoryError`, the page file or total committed-memory headroom is too small. This repository includes a conservative launcher that starts SD.Next without checkpoint autoload and enables state-dict offload before requesting the checkpoint:

```powershell
.\scripts\Start-SDNextLowMemory.ps1 -ComputeDType BF16 -MemoryMode lowvram
```

It requires at least 6 GB of free virtual memory before starting. It deliberately does not close applications or change the Windows page file. Its separate runtime configuration does not overwrite the normal SD.Next `config.json` managed by Stability Matrix. BF16 is the validated compute dtype for this checkpoint and GPU; FP16 generated invalid black images during validation.

## Tested SD.Next API compatibility patch

The tested SD.Next revision has two issues on the API path used by `POS`: `/sdapi/v1/preprocess` declares the wrong response model, and API-created ControlNet units load as FP32 even when the active pipeline uses BF16. The latter causes `mat1 and mat2 must have the same dtype` at the first diffusion step. SD.Next also registers selectable Control scripts only while the Control UI is initialized; the supplied low-memory launcher therefore keeps that tab enabled internally even for API-driven runs.

Stop SD.Next, apply the version-checked patch, and then restart it:

```powershell
.\scripts\Apply-SDNextApiCompatibilityPatch.ps1 `
  -PackagePath '<Stability Matrix data directory>\Packages\SD.Next'

.\scripts\Start-SDNextLowMemory.ps1 -ComputeDType BF16 -MemoryMode lowvram
```

The patch is idempotent, creates timestamped backups inside the SD.Next package, validates Python syntax, and refuses revisions other than `684940e015911efab2911667231946d91fef9f50` unless `-AllowDifferentRevision` is explicitly supplied. A later SD.Next update may make the patch unnecessary or change its target code; review upstream changes instead of bypassing the revision check automatically.

## Run a one-scene pilot first

From the repository root:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\Invoke-IdentityStressTest.ps1 -StartShot 1 -EndShot 1
```

This creates five images for `S01` as an API smoke test. Because the reference itself contains a pool and black swimwear, `S01` is an intentionally easy but biased identity case. Also run the more challenging `S06` or `S10` before committing hours to the full matrix:

```powershell
.\scripts\Invoke-IdentityStressTest.ps1 -StartShot 6 -EndShot 6
```

Inspect the five output variants:

```text
runs/identity-stress-test-v1/S01-TXT.png
runs/identity-stress-test-v1/S01-IPA.png
runs/identity-stress-test-v1/S01-FID.png
runs/identity-stress-test-v1/S01-POS.png
runs/identity-stress-test-v1/S01-FIN.png
```

Open `runs/identity-stress-test-v1/report.html` for a side-by-side view.

## Run all 50 images

```powershell
.\scripts\Invoke-IdentityStressTest.ps1
```

The run is resumable. Existing PNG files are decoded and checked for the expected dimensions before they are skipped, so the same command can continue after an interruption. Existing successful manifest timing is preserved. Use `-Force` only when intentionally replacing existing results.

Useful partial runs:

```powershell
# Generate only the ten text baselines.
.\scripts\Invoke-IdentityStressTest.ps1 -Stages TXT

# Run scenes 3 through 5 across all stages.
.\scripts\Invoke-IdentityStressTest.ps1 -StartShot 3 -EndShot 5

# Retry only independent identity modules for scene 2.
.\scripts\Invoke-IdentityStressTest.ps1 -StartShot 2 -EndShot 2 -Stages IPA,FID -Force
```

`POS` depends on the corresponding `TXT` file. `FIN` depends on the corresponding `POS` file and the locally cached InsightFace/InSwapper assets. The script records a blocked stage in the manifest instead of silently substituting another input.

Stages run across all selected scenes before the next stage begins. This stage-major order reduces repeated heavy-module switching and memory fragmentation on constrained hardware.

## Outputs and audit trail

The output directory contains:

```text
runs/identity-stress-test-v1/
  S01-TXT.png ... S10-FIN.png
  manifest.csv
  evaluation.csv
  report.html
  requests/
  pose-maps/
  detailer-intermediates/
  response-info/
```

- `manifest.csv` records status, runtime, seed, settings, conditioning, filename, and errors.
- `evaluation.csv` provides one 1-to-5 scoring row for every expected image and is never overwritten after creation.
- `requests/` stores every JSON request sent to SD.Next.
- `pose-maps/` stores the extracted OpenPose maps.
- `detailer-intermediates/` preserves the pre-upscale detailer results.
- `response-info/` preserves compact SD.Next generation information without duplicating base64 image payloads.
- `report.html` is regenerated after every scene so partial work remains reviewable.

API image responses are decoded and normalized to real PNG files before saving. This avoids a common mismatch where SD.Next's default JPEG response is stored under a `.png` filename.

Request snapshots contain embedded base64 reference images and can consume substantial disk space. Treat them as provenance-sensitive local records. Large run outputs are intentionally ignored by Git. Commit the configuration, scripts, documentation, selected approved samples, and compact metadata rather than all generated binaries.

## FaceID compatibility note

The tested SD.Next revision exposes a structured FaceID API field with a positional-argument mismatch. This workflow therefore invokes the installed selectable script named `Face: Multiple ID Transfers` with its complete 17-argument contract. This is an explicit compatibility workaround, not a generic promise for every future SD.Next revision.

On the tested GTX 1650 4 GB system, `FaceID Base` remains unavailable in the required offloaded configuration. Its implementation attempts to move the complete pipeline to CUDA and Diffusers rejects that operation after sequential/balanced offload has been activated. `FID` is therefore recorded as failed on this hardware instead of being mislabeled as complete. IP-Adapter Plus Face remains useful as an independent comparison, but the production `FIN` path uses offline FaceSwap after the pose and upscale.

## Why pose and identity are separated

The combined IP-Adapter plus OpenPose request was tested at IP-Adapter scales `0.45`, `0.25`, and `0.20`. At 25 steps it repeatedly ignored the standing OpenPose map and converged to a seated composition. Extending ControlNet guidance from `0.8` to `1.0` did not solve the competition. Eight-step previews could appear compliant and were therefore not reliable approval evidence.

The validated production order is:

1. Generate `POS` with OpenPose only, strength `0.7`, start `0.0`, and end `1.0`.
2. Run the conservative face Detailer on the pose-correct base.
3. Upscale the approved composition to 1024 x 1536 with 2x RealESRGAN Compact.
4. Run `scripts/Invoke-OfflineFaceSwap.py` on the finished pixels using the hash-verified fictional face reference.

This order prevents identity conditioning from changing the body pose, framing, wardrobe, or scene. FaceSwap is intentionally last because a full-body face at 512 x 768 contains too few pixels for a strong transfer. The intermediate files remain available for audit and comparison.

FaceID may be retested on hardware that can run the pipeline without sequential offload, but that path has not been validated by this repository. If a later SD.Next update changes or fixes either contract, validate one `FID` scene before launching the complete matrix. The saved request JSON makes the exact call auditable.

## Why LoRA is not applied to these 50 images

No trained and validated Camila identity LoRA currently exists. Adding an arbitrary style or person LoRA would not represent Camila and would make the comparison scientifically misleading.

The correct LoRA sequence is:

1. Run this matrix.
2. Select a consistent, artifact-free, authorized set of Camila images.
3. Caption and curate the training dataset.
4. Train an identity LoRA against the same SD 1.5 model family.
5. Validate identity, overfitting, anatomy, and memorization.
6. Add a separate `LRA` comparison column with the same ten seeds and prompts.

Until that training pass exists, `TXT`, `IPA`, `FID`, and `POS` remain honest independent measurements. Do not label an output as LoRA-conditioned when no LoRA was loaded.

## Scope and exclusions

This v1 experiment compares individual identity approaches and two composite stages. It is not a single cumulative chain containing every available SD.Next feature:

- `TXT` to `IPA` isolates the addition of IP-Adapter.
- `TXT` to `FID` isolates the alternative FaceID path.
- `TXT` to `POS` measures pose control without identity conditioning during diffusion.
- `POS` to `FIN` adds the Detailer, Upscaler, and offline FaceSwap, so those finishing effects are not independently attributable.
- `FID` is not fed into `POS` or `FIN`; the working low-memory production branch uses offline FaceSwap after composition.
- LoRA, ControlNet Depth, ControlNet Canny, and img2img are not part of this 50-file v1 matrix.

The pose map is extracted from that concept's text-only image. This tests self-retention of a generated pose, not compliance with an independent pose photograph. Reject a `TXT` source with cropped limbs or broken anatomy before treating its OpenPose derivative as valid.

The IP-Adapter input uses face cropping to reduce leakage from the reference's original background and wardrobe.

## Evaluation rubric

Score every output from 1 to 5 on:

- identity continuity: eyes, face shape, freckles, hairline, and apparent age;
- full-body framing: head and feet present without accidental crop;
- anatomy: hands, feet, joints, limb count, and weight distribution;
- pose compliance: whether the requested stance or motion is readable;
- wardrobe compliance: correct garment, opacity, fit, and physical fabric behavior;
- scene compliance: recognizable environment, time of day, and believable light;
- realism: skin texture, lens behavior, shadows, sensor noise, and absence of CGI polish;
- expression: requested emotion without an uncanny or frozen face.

Do not select a winner from facial attractiveness alone. A useful identity pipeline must remain stable across all ten scenes.

## Iterative execution

This script already provides the important persistence behavior: deterministic seeds, saved requests, per-stage error capture, resumable files, and a live HTML report. Run the one-scene pilot, correct any contract or model-download issue, and then rerun the same command until all expected manifest rows are complete.

The optional Ralph Loop plugin belongs to Claude Code and is not executed by Codex Desktop. When using that environment, it can supervise repeated validation, but it must still use a bounded iteration count and the same completion criterion. A suitable command is:

```text
/ralph-loop "Run the documented Camila identity stress test. Start with S01, inspect manifest errors, fix only reproducibility or API-contract defects, resume completed files, and stop only when all 50 expected manifest rows are complete. Output <promise>IDENTITY MATRIX COMPLETE</promise> only after validation." --max-iterations 20 --completion-promise "IDENTITY MATRIX COMPLETE"
```

Never use a loop to bypass failed safety checks, replace provenance requirements, or hide repeated model-loading failures.
