# Project Reference — Photorealism Baseline N9

## Recorded decision

Image N9 is the approved visual baseline for this project.

- File: `samples/baseline-n9.png`
- Model: CyberRealistic v9.0, SD 1.5, pruned FP16
- AutoV2 model hash: `22C7896047`
- Interface/backend: SD.Next managed by Stability Matrix
- Sampler: `DPM++ SDE`
- Sigma schedule: `Karras`
- CFG: `6.0`
- Steps: `25`
- Seed: `231984751`
- Resolution: `512 × 512`
- VAE: `Full`
- Batch size: `1`
- Hires fix: disabled
- Detailer: disabled
- LoRA, ControlNet, IP-Adapter, and input image: none

This combination won a controlled 20-image comparison involving four samplers and five CFG values. The model, positive prompt, negative prompt, seed, step count, resolution, and VAE mode remained fixed.

## Exact positive prompt

```text
RAW unedited candid smartphone photograph, three-quarter body portrait of a fictional clearly adult 23-year-old Brazilian woman from Santa Catarina, dark brown slightly messy hair, brown eyes, natural mature facial features, subtle facial asymmetry, visible realistic skin pores, faint natural blemishes, fine skin texture, minimal makeup, relaxed imperfect posture, wearing a simple black bikini, standing beside a residential pool in Florianopolis, subtropical vegetation, soft overcast Atlantic daylight, realistic shadows, accurate skin tones, spontaneous social media photo, slight lens distortion, imperfect framing, slight sensor grain, no beauty retouching, ordinary real-life photograph
```

## Why the positive prompt worked

### 1. Photographic language appears first

`RAW unedited candid smartphone photograph`

This opening establishes the target domain early: a casual, unedited phone photograph. It pushes the output away from advertising, studio, and rendered aesthetics.

### 2. The subject is explicitly fictional and adult

`fictional clearly adult 23-year-old Brazilian woman`

This defines an adult fictional character rather than a real person. An age number alone does not reliably control apparent age, so `clearly adult` and `natural mature facial features` provide necessary reinforcement.

### 3. Identity cues avoid artificial perfection

`dark brown slightly messy hair, brown eyes, natural mature facial features, subtle facial asymmetry`

Slightly messy hair and facial asymmetry reduce the polished doll-like look often associated with synthetic portraits. Real faces are not perfectly symmetrical.

### 4. Skin microtexture is explicit

`visible realistic skin pores, faint natural blemishes, fine skin texture, minimal makeup`

This is one of the most important blocks. Pores, minor blemishes, fine texture, and minimal makeup introduce visual signals associated with unretouched photography. N9 retained texture without exaggerating blemishes.

### 5. Posture and framing are intentionally imperfect

`relaxed imperfect posture`

This discourages rigid catalog posing. However, the requested `three-quarter body portrait` was not achieved: the result is framed roughly from the bust upward. Framing should therefore be tested separately with a vertical resolution.

### 6. Wardrobe and environment remain simple

`wearing a simple black bikini, standing beside a residential pool in Florianopolis, subtropical vegetation`

A simple black garment reduces fabric and pattern artifacts. The residential pool, vegetation, and background architecture form a coherent environment. `Florianopolis` influences the overall climate and setting but cannot guarantee geographic accuracy.

### 7. Soft natural light supports believable skin

`soft overcast Atlantic daylight, realistic shadows, accurate skin tones`

Overcast daylight reduces harsh highlights, plastic shine, and extreme shadow contrast. It also makes believable skin tones easier to produce.

### 8. Camera imperfections are intentional

`spontaneous social media photo, slight lens distortion, imperfect framing, slight sensor grain`

This group adds plausible capture artifacts: imperfect composition, mild optical distortion, and sensor grain. The word `slight` matters; stronger degradation would make the result look damaged rather than natural.

### 9. The ending reinforces the anti-retouching goal

`no beauty retouching, ordinary real-life photograph`

The final instruction restates that the target is an ordinary photograph rather than a beauty campaign with porcelain skin.

## Exact negative prompt

```text
child, teenager, young-looking, underage, nudity, explicit sexual content, cgi, 3d render, illustration, doll, mannequin, waxy skin, plastic skin, airbrushed skin, oversmoothed skin, glamour retouching, perfect symmetry, uncanny face, artificial eyes, fake teeth, excessive makeup, HDR, oversaturated, fake bokeh, bad anatomy, deformed hands, extra fingers, fused fingers, extra limbs, duplicate person, blurry, low resolution, watermark, text
```

## Why the negative prompt worked

### 1. Age and content boundaries

`child, teenager, young-looking, underage, nudity, explicit sexual content`

This keeps the subject clearly adult and the scene within non-explicit swimwear/lifestyle photography.

### 2. Rendered appearance is rejected

`cgi, 3d render, illustration, doll, mannequin`

These terms suppress visual styles that directly compete with photographic realism.

### 3. Artificial skin is rejected

`waxy skin, plastic skin, airbrushed skin, oversmoothed skin, glamour retouching`

This is the negative counterpart of the positive skin-texture block. The combination of explicit natural texture and explicit rejection of artificial texture was likely a major contributor to the improvement.

### 4. Excessively perfect faces are rejected

`perfect symmetry, uncanny face, artificial eyes, fake teeth, excessive makeup`

This block targets common synthetic-face cues and helps prevent an overly idealized appearance.

### 5. Aggressive post-processing is rejected

`HDR, oversaturated, fake bokeh`

These terms discourage unnatural contrast, saturation, and background blur. They work coherently with overcast lighting and the casual-phone aesthetic.

### 6. General anatomy and output hygiene

`bad anatomy, deformed hands, extra fingers, fused fingers, extra limbs, duplicate person, blurry, low resolution, watermark, text`

This is a general protection layer. The winning composition barely shows hands, so this experiment does not validate hand quality.

## Why configuration N9 won

`DPM++ SDE` produced a less rigid composition and face than DPM++ 2M and a less polished result than several Euler a candidates. At `CFG 6.0`, the checkpoint followed texture, environment, and casual-photography cues without forcing outlines and contrast. N10 at `CFG 6.5` was also strong but looked slightly cleaner and more produced.

CFG does not directly control generation speed. In this experiment, CFG changes had negligible timing impact. CFG controls prompt-guidance strength; values that are too high can produce forced contrast, contours, and details.

## Variables that should remain fixed

1. Keep the checkpoint hash, sampler, Karras schedule, CFG 6.0, and 25 steps.
2. Keep seed `231984751` while refining the same composition.
3. Preserve the natural skin texture, subtle asymmetry, minimal makeup, overcast daylight, and casual-camera blocks.
4. Preserve negative blocks against plastic skin, glamour retouching, perfect symmetry, CGI, and HDR.
5. Change only one variable per experiment and record the result.

## Variables that may change

- Swimwear color or style.
- Environment and time of day, provided the lighting description remains physically coherent.
- Hair, accessories, and expression.
- Seed, when the goal is to explore new compositions.
- Aspect ratio, when the goal is a full-body or three-quarter view.

## Observed limitations

- The output did not deliver the requested three-quarter framing.
- 512 × 512 is suitable for fast comparison but not a final production resolution.
- The test did not validate hands, feet, full-body anatomy, or identity consistency across images.
- The location looks tropical and residential but is not a verifiable representation of Florianopolis or Santa Catarina.
- A text prompt does not guarantee recurring identity. Authorized references, IP-Adapter/FaceID, or a custom LoRA must be evaluated for a persistent character.
- Do not add LoRA, ControlNet, Detailer, and upscaling simultaneously. Validate each component separately.

## Recommended next-test protocol

1. Use N9 as the visual reference.
2. Preserve the entire baseline and test vertical aspect ratio first.
3. Generate a small number of images per stage with a fixed seed.
4. Test skin microtexture with three variants: full block, without `faint natural blemishes`, and without the entire skin block.
5. Compare Detailer disabled versus enabled only after the texture test.
6. Select a winner before starting identity-consistency work.

## Project rule

Realism does not come from adding many adjectives. It comes from coherent capture, lighting, texture, and imperfection cues, validated through experiments in which only one variable changes at a time.
