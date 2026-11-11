#!/bin/zsh
set -euo pipefail
dataset=$1; input=$2; video=$3
root=${0:A:h}
frames=${video:h}/supersplat-frames
rm -rf "$frames"; mkdir -p "$frames"
python3 "$root/make_camera_track.py" "$dataset" "$frames/camera.json"
PATH="$root/runtime/bin:$PATH" "$root/splat-transform/node_modules/.bin/splat-transform" "$input" "$frames/walk.webp" --camera-track "$frames/camera.json" --resolution 720x1280
# Use the bundled static encoder. It is independent from AVFoundation's
# hardware-encoder entitlement and works in the local worker process too.
"$root/splat-transform/node_modules/ffmpeg-static/ffmpeg" -y -framerate 24 -i "$frames/walk.%04d.webp" -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$video"
