# Pipeline reproduzível

## Fluxo

```text
Configuração versionada
        ↓
Validação da API do SD.Next
        ↓
CyberRealistic V9 + prompt + negative prompt
        ↓
DPM++ SDE / Karras / CFG 6.0 / 25 steps / seed fixa
        ↓
VAE Full
        ↓
PNG + metadados da execução
        ↓
Comparação visual e promoção de uma nova baseline
```

## Estágio 1 — baseline

`config/baseline-n9.json` é a fonte de verdade. O script de reprodução lê esse arquivo e envia apenas campos aceitos pelo endpoint `POST /sdapi/v1/txt2img`.

## Estágio 2 — geração controlada

O script `Invoke-SDNextBaseline.ps1` mantém checkpoint, prompt, negative prompt, seed, sampler, scheduler, CFG, steps, resolução e VAE. A imagem retornada em Base64 é salva localmente, junto com um JSON de metadados.

## Estágio 3 — matriz experimental

`Test-SDNextMatrix.ps1` combina:

- Samplers: DPM++ 2M, DPM++ SDE, Euler a e UniPC.
- CFG: 4.5, 5.0, 5.5, 6.0 e 6.5.

Modelo, prompt, negative prompt, seed, scheduler, steps e resolução permanecem fixos. Isso permite atribuir diferenças visuais ao par sampler/CFG com muito mais confiança.

## Estágio 4 — avaliação

Critérios usados na baseline nº 9:

1. Aparência fotográfica cotidiana.
2. Textura de pele sem acabamento plástico.
3. Assimetria facial natural.
4. Iluminação e sombras fisicamente coerentes.
5. Anatomia e proporções convincentes.
6. Ausência de HDR, saturação e bokeh artificiais.
7. Fidelidade ao conceito de personagem fictícia adulta em fotografia de moda/praia não explícita.

## Estágio 5 — promoção de baseline

Uma nova imagem só substitui a nº 9 quando:

- superar a baseline nos critérios definidos;
- tiver parâmetros completos registrados;
- resultar de um teste com apenas uma variável alterada;
- não depender de arquivos ou referências sem origem e autorização registradas.

## Próximos experimentos recomendados

1. Proporção vertical para corrigir o enquadramento de três quartos.
2. Ablação do bloco de microtextura de pele.
3. Detailer desligado versus ligado.
4. Upscale somente depois de escolher a melhor composição.
5. Consistência de identidade com referências autorizadas, testando IP-Adapter/FaceID e depois LoRA própria separadamente.

