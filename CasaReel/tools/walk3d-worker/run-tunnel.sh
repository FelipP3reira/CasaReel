#!/bin/zsh
set -euo pipefail

cd "${0:A:h}"
exec bin/cloudflared tunnel --url http://127.0.0.1:8792
