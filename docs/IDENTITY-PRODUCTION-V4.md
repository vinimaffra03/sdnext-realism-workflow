# Identity Production V4

V4 produces non-explicit lifestyle photographs of the fictional, clearly adult N9 brunette in five Brazilian environments. It is designed for the tested GTX 1650 4 GB system and keeps all generated data on `D:`.

The default API timeout is 90 minutes because a 512x768 IP-Adapter pass can exceed 30 minutes on the tested low-VRAM configuration, including VAE decoding.

The queue guard treats an empty SD.Next job name as idle even when an interrupted request leaves stale step counters in the progress endpoint.

## Design decisions

- CyberRealistic V9 FP16, DPM++ SDE, Karras, CFG 6, 25 steps and Full VAE remain the visual baseline.
- The approved `samples/baseline-n9.png` is the only identity reference.
- Candidate generation is resumable and never overwrites an existing PNG unless `-Force` is explicit.
- The initial pilot compared text-only and IP-Adapter Plus Face. FaceID was attempted once and disabled on the tested 4 GB low-VRAM runtime because it conflicts with SD.Next sequential CPU offload.
- OpenPose is refused unless a shot has an authorized, complete `pose_source` in the configuration.
- InSwapper 128 is not part of V4. Identity similarity is diagnostic and never substitutes for visual QA.
- Face, eye and hand corrections are optional localized inpainting passes. Face/eye passes use IP-Adapter at moderate strength.
- Lanczos and RealESRGAN outputs are always separate review candidates. Neither is automatically declared final.

## Generate the pilot

Launch SD.Next first, then run:

```powershell
.\scripts\Test-IdentityProductionV4.ps1
.\scripts\Start-IdentityProductionV4.ps1 -Mode Pilot
```

The five pilot jobs are:

1. Pool, text only.
2. Pool, IP-Adapter Plus Face.
3. Fitting room, IP-Adapter Plus Face.
4. Cafe, IP-Adapter Plus Face.

The failed FaceID attempt remains recorded in `manifest.csv`; resumptions do not repeat it while `identity.faceid_enabled` is false.

Review `runs/identity-production-v4-brazil/report.html` at full resolution. Do not use identity cosine similarity to approve defects.

The initial pilot showed that applying IP-Adapter to the entire image can dominate pose, wardrobe and location. V4 therefore uses a composition-first pipeline. Validate the strengthened scene prompts without identity conditioning:

```powershell
.\scripts\Start-IdentityProductionV4.ps1 -Mode CompositionPilot
```

Only after a composition passes visual QA is IP-Adapter applied to a localized face mask by the finalizer.

The second composition round front-loads framing, location, wardrobe, pose and expression before the identity and realism blocks. This prevents essential scene terms from being diluted by a long SD 1.5 prompt.

That ordering produced the correct environment but omitted the person. The next controlled round moves the single adult subject and identity block first, followed immediately by framing, location and wardrobe.

## Generate candidates

After the pilot selects the conditioning method, generate candidates in the planned groups:

```powershell
.\scripts\Start-IdentityProductionV4.ps1 -Mode Candidates -Conditioning TXT -CandidateStart 1 -CandidateEnd 3
.\scripts\Start-IdentityProductionV4.ps1 -Mode Candidates -Conditioning TXT -CandidateStart 4 -CandidateEnd 6
.\scripts\Start-IdentityProductionV4.ps1 -Mode Candidates -Conditioning TXT -CandidateStart 7 -CandidateEnd 10
```

Run only one batch at a time. The launcher has a singleton guard: if a V4 runner is already active for the same output directory, it reports that PID and exits without adding a duplicate SD.Next queue. Use `-ShotIds P01,P02` to limit a batch. Existing valid filenames are skipped.

## Finalize selected candidates

Copy `config/identity-production-v4-selection.example.json`, list one approved candidate per shot, and request only necessary corrections. Supported automatic correction labels are `face`, `eyes`, and `hands`.

```powershell
.\scripts\Finalize-IdentityProductionV4.ps1 -SelectionPath '.\config\identity-production-v4-selection.json'
```

The finalizer creates localized masks, preserves the rest of the image, uses IP-Adapter for face/eye inpainting, and writes separate Lanczos and RealESRGAN 2x files under `runs/identity-production-v4-brazil/final-review/`.

The final command requires exactly ten unique selections. Use `-AllowPartial` only when validating the finalization path with one pilot image.

Clothing, reflection, mirror or background defects that cannot be isolated safely are grounds for rejection. Do not repair them with a broad automatic pass.

## Acceptance gate

Approve a candidate only after inspecting the full image and enlarged face, eyes, teeth, hands, feet, fabric, shadows, background and reflections. Ten images are the target, but a defective image must never be accepted to fill the quota. The hard generation ceiling is 100 candidates.
