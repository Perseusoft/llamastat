#!/bin/bash
# Enlaza este repo en el sistema: presets y LaunchAgent del router.
# Idempotente: se puede correr de nuevo tras cambiar algo.
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.local.llama-router"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
XBAR="$HOME/Library/Application Support/xbar/plugins"

mkdir -p "$HOME/models" "$HOME/Library/Logs/llama-router" "$XBAR"

echo "==> presets.ini -> ~/models/presets.ini"
ln -sfn "$REPO/models/presets.ini" "$HOME/models/presets.ini"


# Llamastat reemplaza al plugin; para usarlo igual: ln -sfn "$REPO/xbar/llamacpp.10s.sh" "$XBAR/"

# launchd no lee bien plists symlinkeados: se copia
echo "==> LaunchAgent $LABEL"
/bin/cp -f "$REPO/launchd/$LABEL.plist" "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
# bootout es asíncrono: esperar a que el servicio desaparezca antes de bootstrap
for i in $(seq 1 20); do launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || break; sleep 0.5; done
launchctl bootstrap "gui/$(id -u)" "$PLIST"

open -g "xbar://app.xbarapp.com/refreshAllPlugins" 2>/dev/null || true
echo "Listo."
