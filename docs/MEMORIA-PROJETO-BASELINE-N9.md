# Memória do projeto — baseline de realismo nº 9

## Decisão registrada

A imagem nº 9 passa a ser a baseline visual do projeto.

- Arquivo: `09_DPM-SDE_cfg-6,0_seed-231984751.png`
- Modelo: `CyberRealistic_V9_FP16 [22c7896047]`
- Interface/backend: SD.Next via Stability Matrix
- Sampler: `DPM++ SDE`
- Scheduler/sigma: `Karras`
- CFG: `6.0`
- Steps: `25`
- Seed: `231984751`
- Resolução: `512 × 512`
- VAE: `Full`
- Batch: `1`
- Hires fix: desativado
- Detailer: desativado
- LoRA, ControlNet, IP-Adapter e imagem de entrada: nenhum

Essa combinação venceu uma comparação controlada de 20 imagens: quatro samplers e cinco valores de CFG, com modelo, prompt, negative prompt, seed, steps e resolução fixos.

## Prompt positivo exato

```text
RAW unedited candid smartphone photograph, three-quarter body portrait of a fictional clearly adult 23-year-old Brazilian woman from Santa Catarina, dark brown slightly messy hair, brown eyes, natural mature facial features, subtle facial asymmetry, visible realistic skin pores, faint natural blemishes, fine skin texture, minimal makeup, relaxed imperfect posture, wearing a simple black bikini, standing beside a residential pool in Florianopolis, subtropical vegetation, soft overcast Atlantic daylight, realistic shadows, accurate skin tones, spontaneous social media photo, slight lens distortion, imperfect framing, slight sensor grain, no beauty retouching, ordinary real-life photograph
```

## Por que o prompt positivo funcionou

### 1. Linguagem fotográfica logo no começo

`RAW unedited candid smartphone photograph`

Esse bloco define cedo o domínio visual: fotografia casual, sem edição e com aparência de celular. Ele combate o aspecto de ensaio publicitário e dá prioridade a uma estética cotidiana.

### 2. Pessoa explicitamente adulta e fictícia

`fictional clearly adult 23-year-old Brazilian woman`

Fixa uma personagem adulta e deixa claro que não se trata de uma pessoa real. A idade sozinha não controla perfeitamente a aparência; `clearly adult` e `natural mature facial features` reforçam o resultado pretendido.

### 3. Identidade visual sem perfeição artificial

`dark brown slightly messy hair, brown eyes, natural mature facial features, subtle facial asymmetry`

O cabelo levemente desarrumado, a assimetria e os traços maduros reduzem o visual de boneca. A assimetria é especialmente útil porque rostos excessivamente simétricos costumam denunciar geração por IA.

### 4. Microtextura de pele

`visible realistic skin pores, faint natural blemishes, fine skin texture, minimal makeup`

Esse é um dos blocos mais importantes. Poros, pequenas marcas e pouca maquiagem criam sinais visuais associados a fotografias reais. A nº 9 manteve textura sem exagerar as imperfeições.

### 5. Postura e enquadramento imperfeitos

`relaxed imperfect posture`

Ajuda a evitar pose rígida de catálogo. Contudo, `three-quarter body portrait` não foi obedecido: a imagem final ficou aproximadamente do busto para cima. Isso mostra que o enquadramento ainda precisa ser tratado em um teste separado, preferencialmente em resolução vertical.

### 6. Roupa e cenário simples

`wearing a simple black bikini, standing beside a residential pool in Florianopolis, subtropical vegetation`

Roupa preta simples reduz distrações e artefatos de tecido. Piscina residencial, vegetação subtropical e arquitetura ao fundo criam contexto coerente. `Florianopolis` orienta o clima visual, mas não garante fidelidade geográfica real.

### 7. Luz natural controlada

`soft overcast Atlantic daylight, realistic shadows, accurate skin tones`

A luz nublada é suave e reduz brilhos plásticos, sombras duras e contraste artificial. Também facilita tons de pele mais convincentes.

### 8. Defeitos de câmera intencionais

`spontaneous social media photo, slight lens distortion, imperfect framing, slight sensor grain`

Esse conjunto introduz sinais de captura real: composição não perfeita, leve distorção óptica e ruído de sensor. O modificador `slight` é importante; exagero produziria uma imagem degradada em vez de natural.

### 9. Fechamento anti-retoque

`no beauty retouching, ordinary real-life photograph`

Reforça no final do prompt que o objetivo é uma foto comum, sem acabamento de campanha ou pele de porcelana.

## Negative prompt exato

```text
child, teenager, young-looking, underage, nudity, explicit sexual content, cgi, 3d render, illustration, doll, mannequin, waxy skin, plastic skin, airbrushed skin, oversmoothed skin, glamour retouching, perfect symmetry, uncanny face, artificial eyes, fake teeth, excessive makeup, HDR, oversaturated, fake bokeh, bad anatomy, deformed hands, extra fingers, fused fingers, extra limbs, duplicate person, blurry, low resolution, watermark, text
```

## Por que o negative prompt funcionou

### 1. Controle de idade e conteúdo

`child, teenager, young-looking, underage, nudity, explicit sexual content`

Mantém a personagem claramente adulta e a cena dentro do conceito de moda/praia em biquíni, sem nudez nem conteúdo explícito.

### 2. Bloqueio de aparência renderizada

`cgi, 3d render, illustration, doll, mannequin`

Reduz estilos que competem diretamente com fotografia realista.

### 3. Bloqueio de pele artificial

`waxy skin, plastic skin, airbrushed skin, oversmoothed skin, glamour retouching`

É o complemento negativo do bloco positivo de poros e pequenas marcas. Essa combinação positiva + negativa provavelmente foi um dos principais motivos para a melhoria percebida.

### 4. Bloqueio de rosto excessivamente perfeito

`perfect symmetry, uncanny face, artificial eyes, fake teeth, excessive makeup`

Ataca sinais comuns de “rosto de IA”. Nem todos aparecem na nº 9, mas o bloco ajuda a manter o rosto menos idealizado.

### 5. Bloqueio de pós-processamento exagerado

`HDR, oversaturated, fake bokeh`

Evita contraste, saturação e desfoque de fundo com aparência artificial. Isso combina bem com a luz nublada e a estética de foto casual.

### 6. Proteção anatômica e técnica

`bad anatomy, deformed hands, extra fingers, fused fingers, extra limbs, duplicate person, blurry, low resolution, watermark, text`

É uma camada de higiene geral. Como as mãos praticamente não aparecem na composição vencedora, o teste não valida ainda a qualidade delas.

## Por que a configuração nº 9 venceu

`DPM++ SDE` produziu uma composição e um rosto menos rígidos que os resultados do DPM++ 2M e menos polidos que parte dos resultados de Euler a. Com `CFG 6.0`, o modelo seguiu os sinais de textura, cenário e fotografia casual sem endurecer demais os contornos. Em `CFG 6.5`, a nº 10 ficou muito boa, porém ligeiramente mais limpa/produzida.

O CFG não controla velocidade. Dentro desse teste, mudar o CFG teve impacto desprezível no tempo; ele controla a força de obediência ao texto. Valores altos demais podem produzir contraste, contornos e detalhes forçados.

## Elementos que devem permanecer fixos

Ao desenvolver esta personagem a partir da baseline:

1. Manter modelo, sampler, Karras, CFG 6.0 e 25 steps.
2. Manter a seed `231984751` enquanto estiver refinando a mesma composição.
3. Manter os blocos de textura de pele, assimetria, maquiagem mínima, luz nublada e foto casual.
4. Manter os negativos contra pele plástica, retoque glamouroso, simetria perfeita, CGI e HDR.
5. Alterar apenas uma variável por teste e registrar o resultado.

## Elementos que podem variar

- Cor/estilo do biquíni.
- Ambiente e horário, desde que a descrição de luz continue fisicamente coerente.
- Cabelo, acessórios e expressão.
- Seed, quando o objetivo for descobrir novas composições.
- Proporção vertical, para obter corpo inteiro ou três quartos.

## Limitações observadas

- A imagem não entregou o enquadramento de três quartos solicitado.
- 512 × 512 é adequado para comparação rápida, mas insuficiente como resolução final.
- O teste não avaliou mãos, pés, corpo inteiro nem consistência entre imagens.
- O local parece tropical/residencial, mas não é uma reprodução verificável de Florianópolis ou Santa Catarina.
- Prompt não garante identidade constante; para uma personagem recorrente serão necessários testes com referência autorizada, IP-Adapter/FaceID ou LoRA própria.
- Não adicionar LoRA, ControlNet, detailer e upscale ao mesmo tempo. Cada componente precisa ser validado separadamente para sabermos o que realmente melhora.

## Protocolo para o próximo teste

1. Usar a nº 9 como referência visual.
2. Preservar toda a baseline e testar primeiro a proporção vertical.
3. Gerar poucas imagens por etapa, com seed fixa.
4. Depois testar microtextura com três versões: bloco completo, sem `faint natural blemishes` e sem todo o bloco de pele.
5. Só depois testar correção facial/detailer, comparando ligado e desligado.
6. Escolher uma configuração vencedora antes de iniciar consistência de identidade.

## Regra de ouro do projeto

Realismo não vem de acrescentar muitos adjetivos. Ele vem da coerência entre captura, luz, textura, imperfeições e configurações, validada por testes nos quais apenas uma variável muda de cada vez.
