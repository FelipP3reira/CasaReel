# Histórico de conversas e decisões

> Registro curto de cada sessão de trabalho com o assistente, para não perder contexto entre conversas. Mais recente no topo.

## 2026-11-10 (parte 4): Walk 3D 100% no aparelho, etapa 1 (captura ARKit)
- Decisão do dono: **nada de mandar para o Mac** para gerar o 3D. Captura e treino rodam no iPhone, sem servidor. Vídeos antigos da galeria deixam de servir (não têm pose). Plano em 4 etapas em `design-walkthrough.md` §9.
- `Walk3DKit/Capture`: `ARSceneCapture` (ARKit sem LiDAR, quadros-chave a cada ~12 cm/~8°, até 240, 960 px, JPG sem metadados), `CaptureManifest` (`capture.json` com intrínsecos e pose OpenCV, validado na leitura), `KeyframeSelector` e `PointCloudAccumulator` (`points.bin`).
- Verificado: Walk3DKit 37/37. **Captura não testada no aparelho** (ARKit não roda no simulador); ainda sem tela.
- Commits: sem linha de coautor.

## 2026-11-10 (parte 3): tutorial "Como gravar"
- `FeatureWalk3D/RecordingGuideView.swift`: tutorial em páginas.
  - **Vídeo 3D, 7 páginas:** preparar a casa, configurar a câmera, como segurar, como andar (com planta animada do trajeto), passar pelas portas, o que atrapalha e resumo.
  - **Fotos do Walk 2.5D, 1 página.**
  - Dicas com ✓/✗, respeita "Reduzir Movimento", VoiceOver ("Faça:"/"Evite:").
- Abre sozinho na 1ª vez em Walk 3D (`@AppStorage("walk3d.recordingGuideSeen")`). Botão "Como gravar (tutorial)" no passo 1. Na aba Criar, "Dicas de fotos para o efeito Walk".
- Textos pt-BR + en (86 no FeatureWalk3D). Testes 9/9, incluindo o que confere que todos os ícones SF Symbols existem. App compila sem warnings. **Não conferido visualmente no aparelho.**

## 2026-11-10 (parte 2): tempos de render medidos (simulador, build otimizado, 1080×1920)
- **Walk 3D real (Metal):** a ordenação estava lenta (1,3–1,9 s por quadro). Foi otimizada com buffers diretos e reordenação a cada 3 quadros. Vídeo de 30 s: **~14 s** com 300 mil Gaussians, **~2,3 min** com 1 milhão, ~5 min com 1,5 milhão (pressão de memória). O `convert.py` agora limita a **1 milhão**.
- **Walk 2.5D / templates de fotos (Core Image):** ~23 s de vídeo em ~3,5 min no simulador, o mesmo tempo do template cinematográfico, então o Walk não deixou mais lento. O simulador desenha na CPU e não tem Neural Engine (IA de profundidade: 6 s por foto no simulador; no iPhone deve ser ~0,1 s). **Precisa medir no iPhone 15.**

## 2026-11-10: Walk 3D real (fotos + vídeos → 3D no Mac → vídeo no iPhone)
- Decisões do dono: Walk **grátis com marca d'água**; "fase 2" = unir **fotos e vídeos da galeria** para criar 3D real; **tudo gratuito** (sem servidor pago). Os vídeos gerados pelo app não servem de entrada (movimento simulado), e isso foi explicado e aceito.
- Ferramentas: COLMAP 4 (BSD, Homebrew) + Brush v0.3.0 (Apache-2.0, binário oficial com SHA-256) no Mac; AppleArchive (`.aar`) para levar e trazer os arquivos; Metal no iPhone.
- Código novo:
  - `Packages/Walk3DKit`: `Export/` (FrameSelector, ImageMetrics, SceneExporter), `Archive/SceneArchive` (extração só de arquivos permitidos), `Splat/` (SplatScene, CameraPath, SplatRenderer em Metal, Walk3DVideoRenderer + marca d'água).
  - `Packages/FeatureWalk3D`: Walk3DModel + Walk3DView (3 passos), catálogo pt-BR/en com 34 textos.
  - App: rota `.walk3D` (aba Criar, não acessível por link), card "Walk 3D real" na tela de fotos, `Walk3DScreen`, serviços no `AppEnvironment`, limpeza de temporários no início. `project.pbxproj` com os 2 pacotes novos (IDs `…0E` e `…0F`).
  - `tools/walk3d/`: `setup.sh`, `walk3d.sh`, `convert.py`, `test_convert.py`, README. Binários baixados ficam em `tools/walk3d/bin/` (ignorado no git).
- Verificado: app `BUILD SUCCEEDED` sem warnings; testes Walk3DKit 23/23 (inclui render Metal e vídeo de ponta a ponta), FeatureWalk3D 5/5, Domain 26/26, VideoEngine 38/38; `convert.py` 3/3.
- **Ainda não testado:** o pipeline no Mac com COLMAP/Brush de verdade (o COLMAP não estava instalado) e uma casa real no iPhone 15.
- Próximo passo: rodar `tools/walk3d/setup.sh`, gravar 1–2 vídeos de um cômodo e testar o fluxo completo; medir os tempos reais.

## 2026-11-09 (parte 2): Walk Nível 1 implementado, **ainda não compilado**
- Decisão do dono: pode usar IA gratuita (não precisa ser tudo Apple), desde que a licença permita uso comercial e não tenha custo.
- Modelo escolhido: Depth Anything V2 Small, versão Core ML da própria Apple (`apple/coreml-depth-anything-v2-small`, variante F16P8, Apache-2.0, 24 MB). Roda 100% no iPhone, sem custo de servidor.
- Código novo/alterado:
  - `Domain/Media/DepthEstimation.swift`: protocolo `DepthEstimating`.
  - `MediaKit/Analysis/CoreMLDepthEstimator.swift` + `MediaKit/Resources/DepthAnythingV2SmallF16P8.mlmodelc` (o modelo carrega no primeiro uso).
  - `VideoEngine`: movimento `walk` (campo `parallax`, limite 0–0,3), transição `walk_through`, `Rendering/WalkCompositor.swift` (4 camadas por profundidade + profundidade "de cômodo" de reserva quando o modelo falha), template `walk-tour.json`.
  - `FeatureVideo`: template "Walk 3D" no editor (+ tradução en).
  - `AppEnvironment`: injeta `CoreMLDepthEstimator()` no `VideoEngineRenderer`.
  - Testes: `VideoEngineTests/WalkTests.swift`, `MediaKitTests/DepthEstimationTests.swift`, contagem de templates ajustada (3 → 4).
- **2026-11-10: compilado e testado.** App `BUILD SUCCEEDED` sem warnings; testes VideoEngine 38/38, MediaKit 36/36 (inclui a IA real), FeatureVideo 13/13. O modelo vai dentro do app (`MediaKit_MediaKit.bundle`).
- Como compilar: o Xcode estava com a *pasta* aberta (sem scheme, o BuildProject trava). Abra `CasaReel/CasaReel.xcodeproj`, ou use `xcodebuild` no terminal. Os testes dos pacotes rodam de dentro de `Packages/<Nome>` (`xcodebuild test -scheme <Nome> -destination ...`); os schemes do projeto não têm a ação de teste.
- **Próximo passo:** testar o template "Walk 3D" no iPhone 15 com fotos reais e ajustar a intensidade (`parallax`) pelo resultado visual.
- Pendências: decidir se o Walk é Pro ou grátis; atualizar o README do VideoEngine e o worker do servidor com `walk`/`walk_through`.

## 2026-11-09
- O app da Fase 1 (vídeo a partir de fotos) foi considerado **pronto/perfeito** pelo dono. O contexto da conversa anterior se perdeu; este arquivo foi criado para evitar que isso se repita.
- Novo diferencial pedido: **vídeo "andando pelo lugar" a partir das fotos**.
- Design proposto em `12-diferencial-walkthrough/design-walkthrough.md`: Nível 1 (2.5D no aparelho, recomendado), Nível 2 (IA generativa no servidor, opcional) e Nível 3 (trajeto renderizado a partir do 3D da Fase 2).
- Pendente: decisões abertas listadas no fim do design (modelo de profundidade, plano pago, Nível 2, antecipar Nível 3).
