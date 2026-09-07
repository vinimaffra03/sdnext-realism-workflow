# Claude vs GPT Prompt Comparison

## Objective

Baseline N9 established a successful realism recipe but used a dark-haired, brown-eyed character. The Camila experiment describes a fictional character with honey-blonde, sun-lightened hair, blue-green eyes, and freckles.

The experiment measures two questions:

1. Which fictional character works better visually under the same technical conditions?
2. Which identity description produces more convincing photography?

## Fixed variables

`config/camila-claude-v1.json` was derived from `config/baseline-n9.json`. Among generation-affecting fields, the intended creative difference is the positive prompt's identity block.

```text
CyberRealistic v9.0 FP16   DPM++ SDE   Karras   CFG 6.0
25 steps   512 × 512   Full VAE   Hires fix off   Detailer off
No LoRA, ControlNet, IP-Adapter, or input image
```

The negative prompt remains identical to N9. Changing it would introduce another experimental variable.

## N9 prompt layers

The winning prompt is composed of functional layers. Only the identity description changes:

| Layer | Content | Action |
|---|---|---|
| 1 — Camera and opening | `RAW unedited candid smartphone photograph, three-quarter body portrait of` | Preserved |
| 2 — Identity | Hair, eyes, and facial-character description | Replaced |
| 2b — Realism craft | Facial asymmetry, pores, minor blemishes, fine texture, minimal makeup, relaxed posture | Preserved |
| 3 — Scene | Black swimwear, residential pool, subtropical vegetation, overcast Atlantic light | Preserved |
| 4 — Camera imperfections | Social-media snapshot, mild lens distortion, imperfect framing, sensor grain, no retouching | Preserved |

### Why layer 2b must remain

Layer 2b resembles identity description but is actually the tested realism recipe. Replacing the entire person-description section would also remove pores, asymmetry, minimal makeup, and relaxed posture. The experiment would then measure loss of realism craft rather than identity differences.

The replacement is deliberately narrow: hair, eye color, facial structure, freckles, and related character traits.

### Conflicting studio language is excluded

A studio clause such as the following would conflict with the N9 camera and environment layers:

```text
Plain light grey background, soft even lighting, 85mm lens, unretouched,
natural skin texture, subtle film grain.
```

It introduces a second background, lighting setup, and camera model. Mixing it with casual smartphone capture, outdoor overcast light, lens distortion, and sensor grain would cause the prompt to compete with itself. Redundant skin-texture phrases are also excluded because N9 already contains the tested version.

## Seed strategy

- Image 01 uses seed `231984751`, matching N9.
- Images 02–20 use `231984751 + (index - 1) × 1000`.
- Every seed is deterministic and recorded in `manifest.csv`.

### Important qualification

The same seed with a different prompt does not guarantee the same photograph with different hair. A seed fixes initial noise, not final composition. Image 01 is the most controlled starting point available, not an identical paired image.

The remaining 19 seeds measure reliability: how often the identity prompt succeeds. A prompt that produces one excellent image out of twenty is not yet production-ready.

## Evaluation criteria

The seven baseline criteria remain in force:

1. Ordinary photographic appearance.
2. Natural skin texture without a plastic finish.
3. Plausible facial asymmetry.
4. Physically coherent lighting and shadows.
5. Convincing anatomy and proportions.
6. No artificial HDR, saturation, or bokeh.
7. Fidelity to a fictional, clearly adult, non-explicit concept.

Two additional criteria apply:

8. Identity fidelity: freckles, blue-green eyes, honey-blonde hair, and sun-lightened ends actually appear.
9. Cross-seed consistency: the character remains recognizable rather than becoming a different person in every image.

Criterion 9 is the most important for a recurring character. Prompt-only consistency is not guaranteed. If it fails, the correct conclusion is that authorized-reference IP-Adapter/FaceID or a custom LoRA is required.

## Known limitations

- **512 × 512:** suitable for controlled testing, not final delivery resolution.
- **Framing:** N9 requested a three-quarter view but produced a bust portrait; square aspect ratio is a likely contributor.
- **Hands:** the composition does not meaningfully validate hand quality.
- **Location:** Florianopolis influences visual climate but does not guarantee geographic authenticity.

## Recording a verdict

Record rankings in the generated `manifest.csv`, following the pattern in `metadata/matrix-results.csv`. A new baseline must satisfy the promotion rules in `docs/PIPELINE.md`.
