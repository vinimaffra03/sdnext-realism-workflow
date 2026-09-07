# SD.Next Realism Workflow

Pipeline local e reproduzível para testes de fotografia lifestyle não explícita, com personagem fictícia e claramente adulta. O projeto preserva a baseline nº 9, os prompts, a matriz comparativa e os scripts usados com SD.Next.

## Baseline aprovada

- Checkpoint: `CyberRealistic_V9_FP16 [22c7896047]`
- Sampler: `DPM++ SDE`
- Scheduler/sigma: `Karras`
- CFG: `6.0`
- Steps: `25`
- Seed: `231984751`
- Resolução de teste: `512 × 512`
- VAE: `Full`
- Hires fix e Detailer: desligados
- Sem LoRA, ControlNet, IP-Adapter ou imagem de entrada

A imagem de referência está em `samples/baseline-n9.png`. A análise completa está em `docs/MEMORIA-PROJETO-BASELINE-N9.md`.

O script de reprodução foi validado no ambiente original: a imagem regenerada apresentou o mesmo SHA-256 da baseline, confirmando igualdade byte a byte. Consulte `metadata/VERIFICATION.md`.

## Requisitos

1. Windows com PowerShell 7 ou Windows PowerShell 5.1.
2. Stability Matrix e SD.Next instalados.
3. SD.Next iniciado e acessível em `http://127.0.0.1:7860`.
4. O checkpoint CyberRealistic V9 disponível no SD.Next.

O checkpoint não faz parte deste repositório. Pesos de modelos e credenciais são ignorados pelo Git.

## Testar a conexão

```powershell
./scripts/Test-SDNextConnection.ps1
```

## Reproduzir a baseline nº 9

```powershell
./scripts/Invoke-SDNextBaseline.ps1
```

A nova imagem e seu arquivo de metadados serão gravados em `runs/`. Caso o nome já exista, o script cria um arquivo com timestamp e não sobrescreve o anterior.

## Repetir a matriz de 20 testes

```powershell
./scripts/Test-SDNextMatrix.ps1
```

O teste combina quatro samplers com cinco valores de CFG, mantendo todo o restante fixo. Imagens existentes são preservadas, permitindo retomar uma execução interrompida.

## Estrutura

```text
config/     configuração exata e prompts da baseline
docs/       memória técnica e descrição da pipeline
metadata/   resultados e ranking da matriz original
samples/    baseline, comparativo e 20 imagens originais
scripts/    conexão, reprodução e matriz automatizada
runs/       novas gerações locais, ignoradas pelo Git
```

## Regra experimental

Mude somente uma variável por teste. Durante refinamentos da mesma composição, mantenha a seed fixa. Mude a seed apenas quando o objetivo for explorar outra pose ou composição.
