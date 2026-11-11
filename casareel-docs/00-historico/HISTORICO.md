# Histórico de conversas e decisões

> Registro curto de cada sessão de trabalho com o assistente, para não perder contexto entre conversas. Mais recente no topo.

## 2026-11-10 (parte 9): configuração do Mac de testes
- Instalados localmente, fora do Git e sem alterar o Homebrew do sistema: Cloudflare `cloudflared` 2026.10.7 (SHA-256 verificado) e Brush `brush_app` 0.3.0 para Apple Silicon (SHA-256 verificado). O worker FastAPI e o Quick Tunnel HTTPS foram iniciados e testados com rota autenticada.
- A URL temporária do túnel e uma credencial nova ficam exclusivamente em `Config/Walk3DWorker.xcconfig` e `.env`, ambos ignorados pelo Git. O app voltou a compilar após a configuração.
- Confirmado pelo `--help`: Brush aceita a pasta Nerfstudio criada das poses ARKit e exporta o PLY. Configurado um perfil inicial de 15 mil passos, no máximo 80 quadros a 960 px, adequado ao Mac com 8 GB para o primeiro teste.
- Implementado `tools/walk3d-worker/renderer`, executável macOS com Metal + AVFoundation: lê PLY binário do Brush, percorre as poses ARKit/Nerfstudio e escreve MP4 H.264 vertical. O perfil inicial limita a 120 mil splats para respeitar os 8 GB. O binário compila e o worker foi configurado para acioná-lo; a execução Metal precisa ser validada no Terminal/Xcode normal, pois o ambiente automatizado nega acesso à GPU.
- Diagnóstico do primeiro teste: nenhuma captura chegou ao worker porque o Xcode tratou `//` da URL HTTPS no `.xcconfig` como comentário e colocou somente `https:` no `Info.plist`. Corrigido com a forma `https:/$()/...`; build verificada com URL HTTPS completa no `Info.plist` final.
- Após a correção, o cliente remoto passou a informar progresso durante a compactação/envio (1–4%), mantém pelo menos 5% depois do job aceito e usa limite de 45 s por pedido para não ficar indefinidamente em 0%. Foram adicionados logs `Walk3DRemote` no Console para distinguir compactação, envio aceito e falha de rede.
- O log do iPhone confirmou `NSURLErrorDomain -1001` ao abrir o HTTPS do túnel, sem qualquer pedido no Mac. A causa de configuração identificada foi `ENABLE_OUTGOING_NETWORK_CONNECTIONS=NO` no target CasaReel; alterado para `YES` e build Debug concluída.
- No teste seguinte, o pedido finalmente chegou ao FastAPI, mas ele respondeu 500: `PermissionError` ao criar `/Users/Shared/CasaReelWalk3DJobs`. Os jobs temporários foram movidos para `tools/walk3d-worker/jobs/` (ignorado pelo Git), e worker/túnel foram reiniciados com nova URL HTTPS. Build Debug concluída.
- Diagnóstico do erro `RemoteWalk3DProcessor.Failure erro 3`: o FastAPI recebeu a captura, mas a rejeitou com `BadZipFile: Bad magic number for central directory`. A causa era o escritor ZIP do iPhone gravar as assinaturas ZIP como `Int` de 64 bits em arm64, embora o formato exija quatro bytes. As assinaturas agora são `UInt32` explícitos e há teste que verifica a assinatura e o offset da tabela central no trailer do ZIP. O build para testes no Xcode foi concluído.
- Após o ZIP ser aceito, o endpoint de acompanhamento retornou 500 porque `dataclasses.asdict()` tentava copiar o `Popen` do treino, que contém um lock não serializável. A resposta do job agora é construída apenas com `id`, estado, progresso, mensagem e disponibilidade do vídeo. Novo worker e túnel foram validados externamente (rota autenticada responde 404 para job inexistente); build Debug concluída.
- O erro posterior `Failure erro 4` confirmou que upload/status já funcionam: o `brush_app` foi chamado, mas não encontrou adaptador Metal (`No possible adapter available for backend`). O processo iniciado pelo ambiente automatizado não tem GPU; foi criado `tools/walk3d-worker/start-for-iphone.command` para iniciar o FastAPI/Cloudflare pelo Terminal normal do usuário, atualizar automaticamente o `.xcconfig` e permitir que o Brush use a GPU do Mac. O procedimento foi documentado em `worker-mac-walk3d.md`.
- Para validar o fluxo ponta a ponta no Mac de 8 GB sem esperar o perfil de qualidade, o perfil de teste do `.env` foi reduzido de 15.000 para 1.000 passos, no máximo 48 quadros a 640 px e 250 mil splats. A qualidade é propositalmente inferior; o perfil completo continua documentado e deve voltar após a validação do MP4.
- O perfil rápido concluiu o treino e produziu `scene.ply`; o erro seguinte era no renderizador MP4: o shader Metal em texto tinha a anotação `[[buffer(1)]]` incompleta, gerando `MTLLibraryErrorDomain Code=3`. A anotação foi corrigida e o executável `casareel-walk3d-renderer` foi recompilado e reinstalado no worker. A ferramenta `xcrun metal` não está instalada no Xcode local, então a validação final do shader ocorre na próxima renderização normal do Mac.
- Uma segunda tentativa revelou que o worker ainda chamava o binário antigo: o produto compilado e `bin/casareel-walk3d-renderer` tinham hashes/horários distintos. O binário foi copiado novamente e os SHA-256 agora são idênticos; a próxima renderização invocará de fato o shader corrigido.
- Corrigido o botão “Tentar de novo” do app: após uma falha de job remoto ele tentava somente baixar/renderizar o mesmo job já marcado como falho, devolvendo erro imediato sem novo pedido ao Mac. Agora descarta o identificador remoto e reenvia a captura ARKit que já está preservada, sem obrigar nova gravação. Build Debug concluída.
- O worker passou a preservar os diretórios e logs de jobs falhos/cancelados, e o inicializador registra o hash do renderizador, para que uma falha no iPhone seja diagnosticável no Mac sem expor dados ao aparelho.
- Diagnóstico de um MP4 preto: o arquivo H.264 foi escrito, mas tinha só 17 KB porque o renderizador interpretava a direção frontal das poses com sinal invertido. As posições das câmeras e os splats do Brush estavam no mesmo sistema de coordenadas; apenas a coluna `forward` era negada de novo. Corrigido para usar `+Z`, e o binário do worker foi recompilado/reinstalado. O salvamento na Fototeca falhou como efeito do MP4 praticamente vazio; a permissão de adicionar fotos já está configurada.
- Diagnóstico do erro “Não foi possível gerar o vídeo” posterior: o `AsyncThrowingStream` do app cancelava seu próprio `Task` também quando terminava normalmente. O `defer` interpretava isso como cancelamento do usuário e enviava `DELETE` ao job já treinado, interrompendo a renderização/download. Agora somente a terminação `.cancelled` cancela o job remoto. Build Debug verificada no Xcode.
- O MP4 seguinte confirmou que o fluxo inteiro termina, mas revelou uma limitação do renderizador de protótipo: splats translúcidos eram desenhados na ordem arbitrária do PLY, sem ordenação por profundidade. O worker agora ordena os splats do fundo para a frente para cada pose antes de desenhar o quadro; o binário foi recompilado. Ainda falta implementar a projeção anisotrópica/SH completa antes de considerar a qualidade visual pronta.
- O renderizador foi ampliado para consumir a geometria que o Brush realmente exporta: três log-escalas e quaternion por splat. Para cada câmera, ele projeta a covariância 3D como uma elipse 2D e usa essa elipse no shader, além da ordenação fundo→frente. O executável Release do worker foi recompilado com sucesso. As componentes SH direcionais continuam como melhoria posterior; a cor DC já é suficiente para validar forma, profundidade e estabilidade.

## 2026-11-10 (parte 8): Walk 3D no Mac de testes, automático
- Decisão nova: o iPhone continua capturando com ARKit, mas envia o pacote automaticamente por HTTPS ao Mac privado. O Mac, ligado e com o worker aberto, treina/renderiza localmente; não há GPU alugada, servidor pago ou envio manual de arquivo.
- Adicionado `tools/walk3d-worker`: FastAPI sem Docker, token Bearer obrigatório, uma fila por vez, ZIP com extração segura e conversor de `capture.json` para `transforms.json` Nerfstudio. O comando do Brush e o renderizador MP4 são configuráveis no Mac.
- Adicionado `RemoteWalk3DProcessor`: compacta a captura, envia para o worker, acompanha treino/render e baixa o MP4. URL do túnel e token ficam em `Config/Walk3DWorker.xcconfig`, ignorado pelo Git. A tela informa que a captura vai ao Mac de testes.
- Verificado: app compila; FastAPI inicia e rejeita pedido sem token. Ainda falta configurar o comando real do Brush/renderizador, abrir Cloudflare Tunnel e fazer a primeira execução ponta a ponta.

## 2026-11-11 (parte 3): agulhas e véu nos vídeos do worker do Mac
- **Medido:** no PLY do Brush (6000 passos, 33 mil splats), 22% dos splats são agulhas (eixo maior > 10× o segundo; p99 = 72×) e o maior tem 11,6 m. Na renderização aparecem como riscos brancos/coloridos sobre o quarto.
- **Correção:** `clean_splat.py` roda antes do render (`render_with_supersplat.sh`): eixo maior ≤ 6× o segundo e nenhum eixo > 1 m (as escalas do Brush são logs). Discos achatados (paredes, piso) não mudam; o resto do arquivo é copiado byte a byte. Testes: 3 novos (19 no total).
- **Testado e descartado:** razão 3 (achata bordas finas de porta, piora o corredor); esconder splats grandes e fracos (abre manchas escuras na parede); `--scale-loss-weight 1e-5` no Brush (as agulhas continuam: 23,5% contra 21,9%, só o maior splat cai de 11,6 m para 3,9 m).
- **Resta:** um véu cinza na parede quando a câmera passa perto dela (a parede lisa tem poucos detalhes para o treino fixar). Treinar mais passos ajuda; gravar a 1–2 m das paredes também.
- **Bug achado pelos testes:** um splat com escala NaN era trocado na conta mas não regravado no arquivo.

## 2026-11-11 (parte 2): treino em 6000 passos e abertura do vídeo
- **O "mesma coisa" era o worker antigo:** o worker só lê o `.env` ao iniciar; o job saiu em 1 min com 3,2 mil splats (= 1000 passos). Depois de reiniciar, `--total-steps 6000 --max-frames 80`: ~5 min por vídeo e 15–50 mil splats, quarto nítido (cama, cadeira, monitor, porta, piso).
- **Abertura ruim:** o caminho repetia a gravação inteira, inclusive o trecho colado na porta (borrão marrom por ~5 s). `make_camera_track.py` agora usa só a maior sequência de quadros com ≥ 1,2 m de folga à frente (percentil 20 dos pontos do ARKit num cone de 30°; falhas de até 2 quadros; mínimo de 12 quadros e 25% da gravação, senão mantém tudo). Na gravação medida cortou os ~7 s iniciais; sobra ~1,5 s de cortina translúcida, que é da gravação.
- Testes do worker: 16 (`.venv/bin/python -m unittest test_walk3d_worker`).
- Fora do commit: a otimização do treino em Metal no aparelho (binning em paralelo, meia resolução) ficou no `git stash` ("otimizacao do treino em Metal…"), porque o app agora usa o worker do Mac e o código não foi testado. O servidor pago (`services/walk3d`, App Attest) ficou meio escrito e sem testes, fora do Git, para quando houver receita.

## 2026-11-11: vídeo 3D preto e borrado (worker do Mac) — causas e correção
- **Vídeo todo preto:** o SuperSplat gira o PLY 180° em torno de Z ao carregar; o caminho de câmera estava em coordenadas "cruas" do ARKit, então a câmera ficava fora da cena (360 quadros de 82 bytes). Provado renderizando o mesmo PLY com 4 convenções de eixos: só `(-x,-y,z)` e `(-x,y,-z)` enxergavam a cena. Além disso o `up` vinha do eixo do sensor (deitado), então o vídeo sairia girado.
- **3D borrado (fatia fina de 1 m):** o `points.bin` (pontos do ARKit) era aceito mas nunca usado; sem ele o Brush espalha splats ao acaso perto das câmeras (10 mil splats, caixa de ~1,4 × 0,2 × 0,6 m). O Brush 0.3 usa um `init.ply` na pasta do dataset.
- **Correções (`tools/walk3d-worker`):** `make_camera_track.py` reescrito (referencial do visualizador, horizonte nivelado por gravidade, suavização, velocidade constante, campo de visão de retrato); `init_points.py` + `write_initial_points` no `app.py`; testes em `test_walk3d_worker.py` (8, `unittest`).
- **Medido no Mac (mesma gravação de 22 quadros):** 1000 passos sem init → fatia borrada; 1000 passos com init → cômodo reconhecível mas borrado (47 s); 6000 passos com init → cama, cadeira, notebook, porta e persiana nítidos (4,5 min, 22 mil splats). O `.env` local usa 1000 passos (de propósito, na fase de testes).
- Reiniciar o `start-for-iphone.command` para o worker carregar o código novo.

## 2026-11-10 (parte 7): primeiro teste no iPhone 15 e correção das "agulhas"
- No aparelho: gravar → treinar → vídeo funcionou (cômodo reconhecível), com riscos compridos e borrão; o iPhone esquenta muito; o Metal falha se o app sai da tela. Outra sessão corrigiu o crash em "Salvar na galeria" (PhotoKit na fila errada), adicionou a permissão de adicionar à Fototeca, criou o target `CasaReelTests` e limitou a escala na exportação e no shader.
- Correção de raiz: `backwardStep` limita a forma de cada Gaussian a cada passo (escala de 1 mm a `max(3 cm, 5% da cena)`; eixo mais longo ≤ 8× o segundo). Teste `ShapeLimitTests`; o `exportIsReadableBySplatScene`, que não compilava, foi corrigido.
- Prints do interior da casa tirados do repositório (a pasta `App/` é sincronizada e os levaria para dentro do app); estão em `~/Desktop/CasaReel-prints/`.
- Testes: o assistente não consegue mais rodar o executor do simulador ("Pseudo Terminal Setup Error"); o dono rodou no Xcode (⌘U) Walk3DKit e FeatureWalk3D, sem falhas.

## 2026-11-10 (parte 6): Walk 3D no aparelho, etapa 3 (tela única)
- `FeatureWalk3D`: `Walk3DModel` novo (gravar → treinar → vídeo; protocolo `SceneCapturing` para testar sem câmera), `CaptureView` (câmera em tela cheia + avisos), `Walk3DView` em 2 passos, tutorial ajustado para a gravação no app, catálogo pt-BR/en revisado (37 textos novos, 36 do fluxo do Mac removidos).
- App: `AppEnvironment` com `ARSceneCapture` + `SplatTrainer`; `RootView` liga tudo (câmera pedida só no "Gravar", tela acesa durante o processamento, `reset()` ao sair da conta); `NSCameraUsageDescription`; limpeza de `CasaReelWalk3DCapture` ao abrir o app.
- Removido o fluxo do Mac: `Walk3DKit/Export`, `Archive`, `tools/walk3d`, escolha de fotos/vídeos da galeria no Walk 3D, linhas do `.gitignore`.
- Verificado: Walk3DKit 39/39, FeatureWalk3D 15/15, app compila sem warnings novos. **Não testado no aparelho** (o simulador não tem ARKit).
- A sessão do assistente caiu duas vezes por falta de memória (Mac de 8 GB com Xcode + simulador). Agora o simulador é desligado depois de cada rodada de testes.

## 2026-11-10 (parte 5): Walk 3D no aparelho, etapa 2 (treino em Metal)
- `Walk3DKit/Training`: `TrainingShaders` (preprocess, rasterizeForward, rasterizeBackward com soma por grupo SIMD antes do atômico, backwardStep com Adam), `TrainingSession` (buffers e um passo), `TileBinner` (ordenação por contagem + blocos, ponteiros brutos), `GaussianModel` (início, densificação, exportação), `TrainingView`, `SplatTrainer` (API pública, cronograma, calor, saída).
- Verificado: Walk3DKit 49/49, incluindo conferência dos gradientes por diferenças finitas (cor/opacidade/x < 1%; tamanho/rotação/z 4–7% por causa do corte de alfa 1/255), perda que cai num quadro e treino de ponta a ponta numa captura sintética. App compila sem warnings.
- Tempo no simulador (Release): ~80 ms por passo com 100 mil Gaussians (distribuição na CPU 15–40 ms, GPU ~50 ms). **Falta medir no iPhone 15**; se a distribuição pesar, passar a ordenação para a GPU (etapa 4).

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
