#!/bin/zsh
# CasaReel Walk 3D: one-time setup on the Mac. Everything here is free and open source.
#   COLMAP (BSD-3-Clause) via Homebrew: finds where each photo/frame was taken.
#   Brush v0.3.0 (Apache-2.0), official release binary, checked with its published SHA-256: trains the 3D.
set -euo pipefail

HERE=${0:A:h}
BIN="$HERE/bin"
BRUSH_VERSION="v0.3.0"
BRUSH_ASSET="brush-app-aarch64-apple-darwin.tar.xz"
BRUSH_URL="https://github.com/ArthurBrussee/brush/releases/download/$BRUSH_VERSION/$BRUSH_ASSET"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Este setup é para Macs com Apple Silicon (M1 ou mais novo)." >&2
  exit 1
fi

if ! command -v brew >/dev/null; then
  echo "Instale o Homebrew primeiro: https://brew.sh" >&2
  exit 1
fi

if ! command -v colmap >/dev/null; then
  echo "==> Instalando COLMAP (Homebrew)…"
  brew install colmap
fi
echo "==> COLMAP: $(command -v colmap)"

if [[ ! -x "$BIN/brush_app" ]]; then
  echo "==> Baixando Brush $BRUSH_VERSION…"
  DOWNLOAD=$(mktemp -d /tmp/brush-download.XXXX)
  curl -fL -o "$DOWNLOAD/$BRUSH_ASSET" "$BRUSH_URL"
  curl -fL -o "$DOWNLOAD/$BRUSH_ASSET.sha256" "$BRUSH_URL.sha256"
  EXPECTED=$(awk '{print $1}' "$DOWNLOAD/$BRUSH_ASSET.sha256")
  ACTUAL=$(shasum -a 256 "$DOWNLOAD/$BRUSH_ASSET" | awk '{print $1}')
  if [[ "$EXPECTED" != "$ACTUAL" ]]; then
    echo "SHA-256 do Brush não confere; download descartado." >&2
    rm -rf "$DOWNLOAD"
    exit 1
  fi
  mkdir -p "$DOWNLOAD/unpacked" "$BIN"
  tar -xJf "$DOWNLOAD/$BRUSH_ASSET" -C "$DOWNLOAD/unpacked"
  FOUND=$(find "$DOWNLOAD/unpacked" -type f -name brush_app | head -1)
  if [[ -z "$FOUND" ]]; then
    echo "brush_app não encontrado no pacote do Brush." >&2
    exit 1
  fi
  cp "$FOUND" "$BIN/brush_app"
  chmod +x "$BIN/brush_app"
  # Downloaded with curl, so there is no quarantine flag; remove it anyway in case it was copied by hand.
  xattr -d com.apple.quarantine "$BIN/brush_app" 2>/dev/null || true
  rm -rf "$DOWNLOAD"
fi
echo "==> Brush: $BIN/brush_app"
echo "Pronto. Agora rode: $HERE/walk3d.sh <arquivo .aar exportado pelo app>"
