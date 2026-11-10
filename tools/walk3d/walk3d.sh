#!/bin/zsh
# CasaReel Walk 3D on the Mac: scene .aar from the app -> COLMAP -> Brush -> result .aar back to the app.
#   ./walk3d.sh CasaReel-Walk3D-20261110-1030.aar [--fast]
set -euo pipefail

HERE=${0:A:h}
BRUSH="$HERE/bin/brush_app"
INPUT=${1:-}
STEPS=20000
[[ "${2:-}" == "--fast" ]] && STEPS=7000

if [[ -z "$INPUT" || ! -f "$INPUT" ]]; then
  echo "Uso: $0 <cena exportada pelo app (.aar)> [--fast]" >&2
  exit 2
fi
if ! command -v colmap >/dev/null || [[ ! -x "$BRUSH" ]]; then
  echo "Rode primeiro: $HERE/setup.sh" >&2
  exit 1
fi

NAME=${INPUT:t:r}
WORK="$HOME/CasaReelWalk3D/$NAME"
mkdir -p "$WORK"
log() { echo "==> [$(date +%H:%M:%S)] $*"; }

log "Extraindo $INPUT"
rm -rf "$WORK/input"
mkdir -p "$WORK/input"
aa extract -i "$INPUT" -d "$WORK/input"
IMAGES="$WORK/input/images"
COUNT=$(find "$IMAGES" -name '*.jpg' | wc -l | tr -d ' ')
log "$COUNT imagens"

DB="$WORK/colmap.db"
rm -f "$DB"
# Macs have no CUDA: SIFT runs on the CPU.
log "COLMAP: pontos de interesse dos vídeos (uma câmera por vídeo)"
(cd "$IMAGES" && find . -path './video_*' -name '*.jpg' | sed 's|^\./||' | sort) > "$WORK/videos.txt"
(cd "$IMAGES" && find . -path './photos/*' -name '*.jpg' | sed 's|^\./||' | sort) > "$WORK/photos.txt"
if [[ -s "$WORK/videos.txt" ]]; then
  colmap feature_extractor --database_path "$DB" --image_path "$IMAGES" --image_list_path "$WORK/videos.txt" \
    --ImageReader.single_camera_per_folder 1 --FeatureExtraction.use_gpu 0
fi
if [[ -s "$WORK/photos.txt" ]]; then
  log "COLMAP: pontos de interesse das fotos (cada foto com sua lente)"
  colmap feature_extractor --database_path "$DB" --image_path "$IMAGES" --image_list_path "$WORK/photos.txt" \
    --FeatureExtraction.use_gpu 0
fi

log "COLMAP: comparando todas as imagens entre si (a parte mais demorada)"
colmap exhaustive_matcher --database_path "$DB" --FeatureMatching.use_gpu 0

log "COLMAP: calculando onde cada imagem foi tirada"
rm -rf "$WORK/sparse"
mkdir -p "$WORK/sparse"
if colmap help 2>&1 | grep -q global_mapper; then
  colmap global_mapper --database_path "$DB" --image_path "$IMAGES" --output_path "$WORK/sparse"
else
  colmap mapper --database_path "$DB" --image_path "$IMAGES" --output_path "$WORK/sparse"
fi
# Several partial models can come out; keep the one with the most images.
BEST="" BEST_COUNT=0
for MODEL in "$WORK"/sparse/*(/); do
  rm -rf "$WORK/probe"
  mkdir -p "$WORK/probe"
  colmap model_converter --input_path "$MODEL" --output_path "$WORK/probe" --output_type TXT >/dev/null
  N=$(grep -v '^#' "$WORK/probe/images.txt" | awk 'NR % 2 == 1 && NF >= 10' | wc -l | tr -d ' ')
  if (( N > BEST_COUNT )); then BEST="$MODEL" BEST_COUNT=$N; fi
done
if [[ -z "$BEST" || $BEST_COUNT -lt 15 ]]; then
  echo "COLMAP só conseguiu posicionar $BEST_COUNT imagens. Grave vídeos andando devagar, com bastante sobreposição, e tente de novo." >&2
  exit 1
fi
log "Modelo escolhido: $BEST ($BEST_COUNT de $COUNT imagens posicionadas)"

log "COLMAP: removendo a distorção das lentes"
rm -rf "$WORK/dense"
colmap image_undistorter --image_path "$IMAGES" --input_path "$BEST" --output_path "$WORK/dense" --output_type COLMAP
mkdir -p "$WORK/dense/sparse/0"
mv "$WORK"/dense/sparse/*.bin "$WORK/dense/sparse/0/"
colmap model_converter --input_path "$WORK/dense/sparse/0" --output_path "$WORK/dense/sparse/0" --output_type TXT

log "Brush: treinando o 3D ($STEPS passos; dá para acompanhar a CPU/GPU no Monitor de Atividade)"
rm -rf "$WORK/brush"
mkdir -p "$WORK/brush"
"$BRUSH" "$WORK/dense" --total-steps $STEPS --export-every $STEPS --export-path "$WORK/brush" \
  --export-name "scene.ply" --sh-degree 0 --max-resolution 1600 --max-splats 3000000
PLY=$(find "$WORK/brush" -name '*.ply' | sort | tail -1)
[[ -n "$PLY" ]] || { echo "Brush não exportou o .ply" >&2; exit 1; }

log "Convertendo para o app"
rm -rf "$WORK/result"
python3 -B "$HERE/convert.py" "$PLY" "$WORK/dense/sparse/0" "$WORK/result"
OUTPUT="${INPUT:h}/${NAME}-3D.aar"
aa archive -d "$WORK/result" -o "$OUTPUT"
log "Pronto: $OUTPUT"
echo "Envie esse arquivo para o iPhone (AirDrop → Salvar em Arquivos) e, no app, toque em \"Importar 3D\"."
