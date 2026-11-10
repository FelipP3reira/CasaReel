# Walk 3D no Mac (gratuito)

Monta o 3D de verdade (Gaussian Splatting) a partir das fotos e vídeos que o anfitrião escolheu no app, e devolve um arquivo que o app transforma no vídeo "andando pela casa".

```
iPhone (Criar → Walk 3D)            Mac (este script)                          iPhone
fotos + vídeos ──► CasaReel-Walk3D-….aar ──► COLMAP ──► Brush ──► …-3D.aar ──► "Importar 3D" ──► vídeo MP4
                    (AirDrop)               (posições)  (3D)       (AirDrop)    (renderiza no aparelho)
```

## Programas (todos gratuitos e de código aberto)

| Programa | Licença | Para quê |
|---|---|---|
| [COLMAP](https://colmap.github.io) 4.x (Homebrew) | BSD-3-Clause | Descobre onde cada foto/quadro foi tirado e a lente usada |
| [Brush](https://github.com/ArthurBrussee/brush) v0.3.0 | Apache-2.0 | Treina o 3D (Gaussian Splatting) na GPU do Mac |
| `aa` (já vem no macOS) | Apple | Abre e cria os pacotes `.aar` |
| `python3` (Command Line Tools) | PSF | `convert.py`: deixa o 3D no formato do app |

## Uso

```zsh
cd tools/walk3d
./setup.sh                                  # uma vez: instala COLMAP e baixa o Brush (com conferência de SHA-256)
./walk3d.sh ~/Downloads/CasaReel-Walk3D-20261110-1030.aar          # qualidade normal
./walk3d.sh ~/Downloads/CasaReel-Walk3D-20261110-1030.aar --fast   # teste rápido (menos detalhe)
```

O resultado `…-3D.aar` fica ao lado do arquivo de entrada. Envie por AirDrop para o iPhone, escolha **Salvar em Arquivos** e, no app, toque em **Importar 3D**. Os arquivos de trabalho ficam em `~/CasaReelWalk3D/<nome>/` (apague quando quiser).

## Tempo (Mac M1, 8 GB, estimativa a confirmar no primeiro teste real)

| Etapa | ~240 imagens |
|---|---|
| COLMAP: pontos + comparação de todas as imagens (CPU) | 20–60 min |
| COLMAP: posições + remoção de distorção | 5–15 min |
| Brush: 20.000 passos (`--fast`: 7.000) | 20–60 min (`--fast`: 8–20 min) |

## Dicas de gravação (o que mais muda o resultado)
- Andar **devagar**, celular na altura do peito, filmando em sequência de um cômodo para o outro (passando pelas portas).
- Bastante luz; evitar contra-luz de janelas e espelhos grandes.
- Sem pessoas nem documentos à vista.
- Fotos do anúncio ajudam no detalhe, mas sozinhas raramente bastam: o 3D precisa de sobreposição entre as imagens, e o vídeo dá isso.

## Formatos
- **Entrada** (`CasaReel-Walk3D-*.aar`): `manifest.json` + `images/photos/photo_NNN.jpg` + `images/video_NN/frame_NNNNN.jpg`. JPEGs regravados sem metadados (sem GPS/EXIF).
- **Saída** (`*-3D.aar`): `scene.splat` (32 bytes por Gaussiana; ver o cabeçalho de `convert.py`) + `path.json` (poses do COLMAP, câmera→mundo, eixos OpenCV).
- O app só extrai esses dois arquivos de um `.aar` (qualquer outra entrada é ignorada) e valida tudo antes de usar.

## Testes
```zsh
python3 -B -m unittest test_convert
```
