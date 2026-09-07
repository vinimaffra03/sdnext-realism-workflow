# Reproducible Pipeline

## Flow

```text
Versioned configuration
        ↓
SD.Next API and checkpoint-hash validation
        ↓
CyberRealistic v9.0 + positive prompt + negative prompt
        ↓
DPM++ SDE / Karras / CFG 6.0 / 25 steps / fixed seed
        ↓
Full VAE decode
        ↓
PNG image + JSON execution metadata
        ↓
Visual comparison and baseline promotion
```

## Stage 1 — Versioned baseline

`config/baseline-n9.json` is the source of truth. It contains the checkpoint hashes, prompts, sampling settings, seed, resolution, and feature switches.

The scripts query `GET /sdapi/v1/sd-models` and locate the checkpoint by SHA-256 or AutoV2 hash. The local filename may therefore differ from the filename used in the original environment.

## Stage 2 — Controlled generation

`scripts/Invoke-SDNextBaseline.ps1` sends only supported fields to `POST /sdapi/v1/txt2img`. It saves the returned Base64 image as a PNG and writes a JSON metadata sidecar.

`scripts/Run-Workflow.ps1` is the main entry point. It validates the API and exact checkpoint before invoking baseline generation.

## Stage 3 — Experimental matrix

`scripts/Test-SDNextMatrix.ps1` combines:

- Samplers: DPM++ 2M, DPM++ SDE, Euler a, and UniPC.
- CFG values: 4.5, 5.0, 5.5, 6.0, and 6.5.

The checkpoint, prompts, seed, sigma schedule, step count, resolution, and VAE mode remain fixed. This makes differences much more attributable to the sampler/CFG pair.

## Stage 4 — Evaluation

The N9 baseline was evaluated using these criteria:

1. Ordinary photographic appearance.
2. Natural skin texture without a plastic finish.
3. Plausible facial asymmetry.
4. Physically coherent lighting and shadows.
5. Convincing anatomy and proportions.
6. No artificial HDR, saturation, or bokeh.
7. Fidelity to a fictional, clearly adult, non-explicit swimwear/lifestyle concept.

## Stage 5 — Baseline promotion

A new image replaces N9 only when it:

- outperforms the baseline under the documented criteria;
- has complete generation parameters;
- results from an experiment that changes only one variable;
- does not depend on unlicensed or unauthorized source material.

## Recommended next experiments

1. Test a vertical aspect ratio to correct three-quarter framing.
2. Run an ablation study on the skin-microtexture block.
3. Compare Detailer disabled versus enabled.
4. Upscale only after selecting the best composition.
5. Test recurring identity using authorized references: IP-Adapter/FaceID first, then a separately evaluated custom LoRA.

