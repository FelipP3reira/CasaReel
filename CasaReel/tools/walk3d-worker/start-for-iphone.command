#!/bin/zsh
# Starts the private Walk 3D worker from the logged-in Mac session.
# Run this file in Terminal (not from Xcode's debugger): Brush needs the
# normal user Metal session to find the Apple GPU.
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h:h}
cd "$script_dir"

if [[ ! -f .env || ! -x .venv/bin/uvicorn || ! -x bin/cloudflared || ! -x bin/brush_app ]]; then
    print -u2 "Worker incompleto. Execute primeiro a configuração documentada em worker-mac-walk3d.md."
    exit 1
fi

set -a
source .env
set +a

# Use the production-quality Gaussian renderer. The older native renderer is
# retained only as a development fallback; SuperSplat handles SH, covariance
# projection and GPU sorting for the Brush PLY.
export WALK3D_RENDER_COMMAND="$script_dir/render_with_supersplat.sh {dataset} {output}/scene.ply {video}"

if [[ -z "${CASAREEL_WALK3D_TOKEN:-}" ]]; then
    print -u2 "CASAREEL_WALK3D_TOKEN não está definido no arquivo .env."
    exit 1
fi

port=8793
tunnel_log=$(mktemp -t casareel-walk3d-tunnel)
server_log="$script_dir/worker-server.log"
worker_pid=""
tunnel_pid=""
tail_pid=""

cleanup() {
    [[ -n "$tail_pid" ]] && kill "$tail_pid" 2>/dev/null || true
    [[ -n "$tunnel_pid" ]] && kill "$tunnel_pid" 2>/dev/null || true
    [[ -n "$worker_pid" ]] && kill "$worker_pid" 2>/dev/null || true
    rm -f "$tunnel_log"
}
trap cleanup EXIT INT TERM

: > "$server_log"
renderer_hash=$(shasum -a 256 bin/casareel-walk3d-renderer | awk '{print $1}')
print -r -- "CasaReel renderer SHA-256: $renderer_hash" >> "$server_log"
print -r -- "Worker mode: retains failed and cancelled job logs for diagnosis." >> "$server_log"
.venv/bin/uvicorn app:app --host 127.0.0.1 --port "$port" >>"$server_log" 2>&1 &
worker_pid=$!
tail -n 0 -f "$server_log" &
tail_pid=$!
bin/cloudflared tunnel --url "http://127.0.0.1:$port" >"$tunnel_log" 2>&1 &
tunnel_pid=$!

tunnel_url=""
for _ in {1..30}; do
    tunnel_url=$(grep -Eo 'https://[-a-z0-9]+\.trycloudflare\.com' "$tunnel_log" | head -n 1 || true)
    [[ -n "$tunnel_url" ]] && break
    sleep 1
done

if [[ -z "$tunnel_url" ]]; then
    print -u2 "Não foi possível abrir o túnel Cloudflare."
    tail -n 30 "$tunnel_log" >&2
    exit 1
fi

# Xcode treats a literal // inside .xcconfig as a comment; preserve it with $().
host=${tunnel_url#https://}
printf '%s\n' \
    '// Valores locais de desenvolvimento. Este arquivo é ignorado pelo Git.' \
    "WALK3D_WORKER_URL = https:/\$()/$host" \
    "WALK3D_WORKER_TOKEN = $CASAREEL_WALK3D_TOKEN" \
    > "$project_dir/Config/Walk3DWorker.xcconfig"

print "Walk 3D pronto no Mac, com GPU Metal disponível."
print "No Xcode, pressione ⌘R para instalar a configuração atualizada no iPhone."
print "Deixe esta janela aberta durante todo o treino. Para encerrar, pressione Control-C."

wait "$worker_pid"
