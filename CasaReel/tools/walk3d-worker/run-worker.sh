#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
set -a
source .env
set +a
exec .venv/bin/uvicorn app:app --host 127.0.0.1 --port 8792
