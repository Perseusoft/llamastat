#!/bin/bash
# Installs the llama.cpp router as a LaunchAgent (starts at login, restarts if it crashes).
# Usage: ./install.sh [models-dir]   (default: ~/models). Safe to re-run.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
MODELS="${1:-$HOME/models}"
LABEL="com.local.llama-router"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LLAMA_SERVER="$(command -v llama-server || true)"
[ -n "$LLAMA_SERVER" ] || { echo "llama-server not found. Install it first: brew install llama.cpp"; exit 1; }

mkdir -p "$MODELS" "$HOME/Library/Logs/llama-router" "$HOME/Library/LaunchAgents"
if [ ! -f "$MODELS/presets.ini" ]; then
  sed "s#__MODELS__#$MODELS#g" "$HERE/../presets.example.ini" > "$MODELS/presets.ini"
  echo "==> Created $MODELS/presets.ini (edit it to list your .gguf models)"
fi

sed -e "s#__LLAMA_SERVER__#$LLAMA_SERVER#g" -e "s#__MODELS__#$MODELS#g" -e "s#__HOME__#$HOME#g" \
  "$HERE/$LABEL.plist" > "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
# bootout is async: wait for the service to go away before bootstrapping again.
for _ in $(seq 1 20); do launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || break; sleep 0.5; done
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "==> Router running on http://127.0.0.1:8080 (logs: ~/Library/Logs/llama-router/)"
