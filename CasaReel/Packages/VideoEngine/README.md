# VideoEngine

Render de vídeo **no aparelho**: template → linha do tempo → quadros → MP4 (+ música) → miniatura e SHA-256. O contrato público (`VideoRenderer`, `VideoRenderRequest`, `RenderEvent`, `RenderedVideo`) fica no `Domain`; os detalhes do template ficam aqui.

## Pipeline

| Etapa | Tipo | Observações |
|---|---|---|
| Template | `TemplateSpec`, `TemplateLibrary` | JSON versionado (docs/04, seção 3). Só dados: enums desconhecidos fazem a decodificação falhar. Limites duros em `TemplateLimits` (≤ 180 s, cenas de 1–8 s, ≤ 60 cenas, zoom 1–2×, transição ≤ 2 s e ≤ metade da cena) |
| Assinatura | `TemplatePackage` | `{"payload": base64(bytes do JSON), "signature": base64(Ed25519(payload))}`. Assinar os bytes exatos evita depender de JSON canônico. Templates embarcados são confiáveis (fazem parte do app assinado); baixados exigem assinatura válida e só substituem versões mais antigas |
| Planejamento | `MotionPlanner`, `SceneTimeline` | Funções puras. Recorte com o aspecto de saída, centrado na região de interesse (saliency do P09), nunca fora da foto e deslocado para não cortar rostos. Cenas do template se repetem em ciclo sobre as fotos; durações escalam para a duração alvo |
| Quadros | `FrameRenderer` | Core Image com um único `CIContext`. Só as fotos em cena são decodificadas (no máximo 2), reduzidas a 1,6× o lado maior da saída. Transições: corte, crossfade, dip-to-black e slide. Legenda por cômodo, título de abertura e marca d'água desenhados como texto simples (nunca interpretado), com limite de tamanho |
| Gravação | `VideoWriter` | `AVAssetWriter` + pool de `CVPixelBuffer`, H.264 (HEVC opcional), 1080×1920 ou 1920×1080, 30 fps, ~10 Mbit/s. Cancelamento a cada quadro; arquivo parcial apagado |
| Calor | `ThermalMonitoring` | `.serious` pausa (evento `pausedForHeat`) até esfriar, por até 60 s; `.critical` aborta com `RenderError.overheated` |
| Música | `AudioMixer` | Repete ou corta a trilha até a duração do vídeo, fade-in de 0,5 s e fade-out do template, e remuxa sem recodificar o vídeo |
| Saída | `VideoEngineRenderer` | Um render por vez (`RenderQueue`), tela acesa durante o render, miniatura JPEG 1280×720 (ou 720×1280) sem metadados e SHA-256 do MP4 |

### Por que quadros desenhados, e não `AVVideoCompositing`

O P10 sugere um compositor customizado. Esse caminho supõe faixas de vídeo de origem numa `AVComposition`; aqui só há fotos. Desenhar cada quadro com Core Image e gravá-lo com `AVAssetWriter` dá o mesmo controle (movimento, transições, sobreposições) com menos peças e sem faixas fictícias.

## Easing (o worker do servidor deve usar as mesmas fórmulas)

| Nome | Fórmula |
|---|---|
| `linear` | t |
| `easeIn` | t² |
| `easeOut` | 1 − (1 − t)² |
| `easeInOut` | 3t² − 2t³ |

`motion.from`/`to` = `[x, y, zoom]`: x e y entre −1 e 1 deslocam o recorte pelo espaço livre ao redor do foco; zoom ≥ 1 aproxima.

## Templates embarcados

| Slug | Estilo | Formatos |
|---|---|---|
| `classic-clean` | Zoom suave, crossfade | 9:16 e 16:9 |
| `cinematic-soft` | Pan lento, dip-to-black | 9:16 e 16:9 |
| `dynamic-social` | Cortes rápidos de 1,5 s (≈ 3 batidas a 120 BPM) e slide | 9:16 |

## Pendências

- **Biblioteca de músicas licenciadas.** Nenhuma trilha está no repositório (licença comercial para redes sociais ainda não contratada). Sem trilha, o vídeo sai mudo; o `AudioMixer` já funciona com qualquer arquivo local e é testado com um tom gerado.
- **Sincronia com a batida** em `dynamic-social` usa durações fixas; marcar batidas por trilha virá com a biblioteca de músicas.
- **Desempenho no iPhone 15** (meta: 30 s de vídeo em ≤ 2 min, pico < 1,2 GB) precisa ser medido no aparelho com o Instruments; o simulador desenha na CPU e não é representativo.
