# Worker Walk 3D no Mac — ambiente de testes

## Decisão

Durante os testes, o iPhone captura a casa com ARKit e envia automaticamente o pacote ao Mac privado. O Mac treina os Gaussian splats localmente e devolve o MP4. Não há upload manual, GPU alugada ou custo de servidor.

O serviço canônico nesta fase é `CasaReel/tools/walk3d-worker`. O diretório `services/walk3d` não participa: ele é um esqueleto separado para a futura arquitetura com App Attest, R2 e RunPod e ainda não contém uma aplicação API executável.

## Contrato HTTP

Todos os pedidos exigem `Authorization: Bearer <token>`.

| Método | Rota | Função |
|---|---|---|
| `POST` | `/v1/walk3d/jobs` | Corpo ZIP da captura: cria o job. |
| `GET` | `/v1/walk3d/jobs/{id}` | Estado: `queued`, `training`, `rendering`, `finished`, `failed` ou `cancelled`. |
| `GET` | `/v1/walk3d/jobs/{id}/video` | Baixa o MP4 concluído. |
| `DELETE` | `/v1/walk3d/jobs/{id}` | Cancela o job e remove os arquivos locais. |

O ZIP contém somente `capture.json`, `points.bin` e `frames/frame_XXXXX.jpg`. O servidor verifica nomes, quantidade de arquivos e caminhos antes de extrair.

## Preparar o Mac

```sh
cd /Users/felipepereira/Desktop/3DandB/CasaReel/tools/walk3d-worker
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example .env
```

Edite `.env` — nunca o adicione ao Git:

```sh
CASAREEL_WALK3D_TOKEN=<token-aleatorio-com-32-ou-mais-caracteres>
WALK3D_DATA_DIR=/Users/Shared/CasaReelWalk3DJobs
WALK3D_RETENTION_HOURS=24
BRUSH_TRAIN_COMMAND='<caminho>/brush_app {dataset} --total-steps 15000 --max-frames 80 --max-resolution 960 --max-splats 1000000 --export-every 15000 --export-path {output} --export-name scene.ply'
WALK3D_RENDER_COMMAND=<comando-que-grava-{video}>
```

O worker converte automaticamente a pose OpenCV em colunas gravada pelo iPhone para a pose OpenGL/ARKit em linhas de `transforms.json` Nerfstudio. Assim, o Brush recebe câmeras conhecidas e não executa COLMAP.

O teste no Mac de desenvolvimento usa o binário oficial `brush_app` 0.3.0 para Apple Silicon, guardado localmente em `CasaReel/tools/walk3d-worker/bin/` e ignorado pelo Git. O SHA-256 conferido do arquivo oficial é `65b2631398c839be3c1d4d7160fe2326389dec87830aac0710985e6690a1048c`. O comando acima foi confirmado com `brush_app --help`.

O Brush recebe Nerfstudio e produz o PLY, mas a sua CLI oficial não fornece uma exportação MP4 automática de uma trajetória. Para isso, foi criado o pacote local `tools/walk3d-worker/renderer`: ele lê o PLY binário padrão do Brush e `transforms.json`, usa Metal para projetar os Gaussian splats ao longo das poses ARKit e usa AVFoundation para escrever um MP4 H.264 vertical (720×1280, 24 fps). É um render 3D real, não um vídeo estático. Para caber no Mac de 8 GB, usa no máximo 120 mil splats na primeira versão.

Compile e instale o renderizador após atualizar o código:

```sh
cd /Users/felipepereira/Desktop/3DandB/CasaReel/tools/walk3d-worker/renderer
CLANG_MODULE_CACHE_PATH=/private/tmp/casareel-swift-module-cache swift build -c release --disable-sandbox
cp .build/release/casareel-walk3d-renderer ../bin/
```

Enquanto `WALK3D_RENDER_COMMAND` estiver vazio, o worker devolve `503 worker_not_ready` **antes** de receber a captura. Assim, ele não inicia um treino longo que inevitavelmente falharia na renderização.

Inicie a API:

```sh
set -a; source .env; set +a
./run-worker.sh
```

## Expor apenas para o iPhone de teste

Use o iniciador único no **Terminal normal do macOS** (duplo clique em
`start-for-iphone.command`, ou execute o comando abaixo). Não o inicie pelo
debugger do Xcode/Codex: esse ambiente pode negar acesso à GPU Metal e o Brush
encerra com “No possible adapter available for backend”.

```sh
cd /Users/felipepereira/Desktop/3DandB/CasaReel/tools/walk3d-worker
./start-for-iphone.command
```

Ele inicia o FastAPI e o Quick Tunnel, espera a URL HTTPS e atualiza sozinho o
arquivo local e ignorado `CasaReel/Config/Walk3DWorker.xcconfig`. Em seguida,
pressione `⌘R` no Xcode para instalar no iPhone a URL recém-criada. Deixe essa
janela do Terminal aberta durante toda a gravação, treino e renderização.

O iniciador escreve `https:/$()/...` no `.xcconfig`, pois o `//` puro é tratado
como comentário pelo Xcode e produziria apenas `https:` no `Info.plist`.

No Xcode, execute o esquema Debug no iPhone. O fluxo é: gravar → concluir → enviar/treinar no Mac → renderizar no Mac → vídeo no app.

## Segurança e limpeza

- Não abra a porta 8789 diretamente na internet; use HTTPS pelo túnel e token aleatório.
- Não versione `.env`, `Walk3DWorker.xcconfig`, vídeos, capturas nem a pasta de jobs.
- O job cancelado é apagado imediatamente. Para jobs concluídos, apagar a pasta `WALK3D_DATA_DIR` periodicamente até a retenção automática ser adicionada.
- A captura agora deixa o iPhone durante o teste; a interface do app declara isso. Não usar este modo para produção sem autenticação por conta, App Attest e política de retenção.

## Verificação feita em 10-11-2026

- O worker inicia no Python 3.9 disponível no Mac.
- Sem token, a API responde `401`; com token, a rota autenticada responde corretamente através do Quick Tunnel HTTPS.
- O `cloudflared` oficial 2026.10.7 foi instalado apenas na pasta ignorada do worker; SHA-256 conferido: `3586ccf397e98e5f437e60e7c307ca6ac463e110580503af8bb8e6f9ebf831bd`.
- Corrigida a URL do túnel no `.xcconfig`: o `Info.plist` Debug gerado agora contém a URL HTTPS completa, em vez de apenas `https:`.
- O app CasaReel compila, inclusive build para testes.
- O renderizador Metal/AVFoundation compila como executável macOS e o worker está configurado para chamá-lo após o Brush.
- A execução Metal não pôde ser validada dentro do ambiente automatizado, que nega GPU a processos de terminal (`MTLCreateSystemDefaultDevice()` retorna vazio). O iniciador `start-for-iphone.command` existe para executar pelo Terminal normal, no contexto gráfico do usuário, e então validar uma captura real do iPhone 15.
