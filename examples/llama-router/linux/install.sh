#!/bin/bash
# Installs the llama.cpp router as a systemd --user service.
# Usage: ./install.sh [models-dir]   (default: ~/models). Safe to re-run.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
MODELS="${1:-$HOME/models}"
UNIT_DIR="$HOME/.config/systemd/user"
LLAMA_SERVER="$(command -v llama-server || true)"
[ -n "$LLAMA_SERVER" ] || { echo "llama-server not found. See https://github.com/ggml-org/llama.cpp#quick-start"; exit 1; }

mkdir -p "$MODELS" "$UNIT_DIR"
if [ ! -f "$MODELS/presets.ini" ]; then
  sed "s#__MODELS__#$MODELS#g" "$HERE/../presets.example.ini" > "$MODELS/presets.ini"
  echo "==> Created $MODELS/presets.ini (edit it to list your .gguf models)"
fi

sed -e "s#__LLAMA_SERVER__#$LLAMA_SERVER#g" -e "s#__MODELS__#$MODELS#g" "$HERE/llama-router.service" > "$UNIT_DIR/llama-router.service"
systemctl --user daemon-reload
systemctl --user enable --now llama-router.service
echo "==> Router running on http://127.0.0.1:8080 (logs: journalctl --user -u llama-router)"
