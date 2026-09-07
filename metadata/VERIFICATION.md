# Verificação de reprodução

Em 2026-09-07, `scripts/Invoke-SDNextBaseline.ps1` foi executado contra o SD.Next local com a configuração versionada em `config/baseline-n9.json`.

- Tempo da execução de verificação: 37,8 segundos.
- SHA-256 da baseline original: `A13F6FA67F26B22B53C848336152C10F1AFB3D8EC7AED76E4DA73D9606E8125E`
- SHA-256 da nova reprodução: `A13F6FA67F26B22B53C848336152C10F1AFB3D8EC7AED76E4DA73D9606E8125E`
- Resultado: arquivos byte a byte idênticos.

Isso confirma a reprodução determinística no ambiente atual. Atualizações do SD.Next, PyTorch, CUDA, checkpoint ou parâmetros podem alterar o resultado no futuro mesmo com a mesma seed.
