# Reproduction Verification

On 2026-09-07, `scripts/Invoke-SDNextBaseline.ps1` was executed against the local SD.Next instance using `config/baseline-n9.json`.

- Verification generation time: 37.8 seconds.
- Original baseline SHA-256: `A13F6FA67F26B22B53C848336152C10F1AFB3D8EC7AED76E4DA73D9606E8125E`
- Regenerated image SHA-256: `A13F6FA67F26B22B53C848336152C10F1AFB3D8EC7AED76E4DA73D9606E8125E`
- Result: the files were byte-for-byte identical.

This confirms deterministic reproduction in the original environment. Future SD.Next, PyTorch, CUDA, checkpoint, or parameter changes may alter results even when the seed remains the same.

After the English packaging and hash-based checkpoint resolver were added, `scripts/Run-Workflow.ps1` was tested end to end. It detected the required checkpoint by hash, validated the API, generated the image in 51.3 seconds, and again produced SHA-256 `A13F6FA67F26B22B53C848336152C10F1AFB3D8EC7AED76E4DA73D9606E8125E`.
