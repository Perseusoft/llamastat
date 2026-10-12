#!/bin/bash
# Levanta el stack local: router llama.cpp + xbar (icono barra de menu)
set -e

LABEL="com.local.llama-router"
URL="http://127.0.0.1:8080"

echo "==> Router llama.cpp..."
if ! launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/$LABEL.plist"
fi

echo "==> xbar..."
pgrep -x xbar >/dev/null || open -a xbar

echo "==> Esperando a que el router responda..."
for i in $(seq 1 15); do
  curl -s "$URL/health" >/dev/null && break
  sleep 1
done

echo "==> Modelos:"
curl -s "$URL/v1/models" | /opt/homebrew/bin/python3.14 -c 'import json,sys; [print(" ", m["id"], "-", m["status"]["value"]) for m in json.load(sys.stdin)["data"]]'
echo ""
echo "Listo. API en $URL (OpenAI /v1 y Anthropic /v1/messages)"
