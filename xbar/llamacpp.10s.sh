#!/bin/bash
# <xbar.title>llama.cpp Router</xbar.title>
# <xbar.desc>Estado del router llama.cpp (com.local.llama-router): modelo cargado, RAM, cargar/descargar</xbar.desc>
# <xbar.author>joseespana</xbar.author>

LABEL="com.local.llama-router"
URL="http://127.0.0.1:8080"
PY="/opt/homebrew/bin/python3.14"
SELF="$0"
UIDN=$(id -u)

# Acciones invocadas desde el menú
case "$1" in
  load|unload)
    /usr/bin/curl -s -m 120 -X POST "$URL/models/$1" -H 'content-type: application/json' \
      -d "{\"model\":\"$2\"}" >/dev/null
    exit 0 ;;
  # KeepAlive=true en el plist: "kill" lo relanzaría, así que hay que hacer bootout/bootstrap
  start) launchctl bootstrap "gui/$UIDN" "$HOME/Library/LaunchAgents/$LABEL.plist"; exit 0 ;;
  stop) launchctl bootout "gui/$UIDN/$LABEL"; exit 0 ;;
  restart) launchctl kickstart -k "gui/$UIDN/$LABEL"; exit 0 ;;
esac

MODELS=$(/usr/bin/curl -s -m 3 "$URL/v1/models")
SWAP=$(sysctl -n vm.swapusage | awk '{print $6}')
FREE=$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/ {print $2}')

if [ -z "$MODELS" ]; then
  echo "🦙 OFF"
  echo "---"
  echo "Router llama.cpp: detenido"
  echo "Iniciar | bash='$SELF' param1=start terminal=false refresh=true"
  exit 0
fi

LOADED=$(echo "$MODELS" | "$PY" -c 'import json,sys; print(" ".join(m["id"] for m in json.load(sys.stdin)["data"] if m["status"]["value"] in ("loaded","loading")))')
ALL=$(echo "$MODELS" | "$PY" -c 'import json,sys; [print(m["id"], m["status"]["value"]) for m in json.load(sys.stdin)["data"]]')

if [ -n "$LOADED" ]; then echo "🦙 $LOADED"; else echo "🦙 idle"; fi
echo "---"
echo "Router llama.cpp: en ejecución (:8080)"
echo "RAM libre: $FREE · Swap usado: $SWAP"
echo "---"
while read -r id status; do
  if [ "$status" = "loaded" ] || [ "$status" = "loading" ]; then
    echo "● $id ($status)"
    echo "--Descargar | bash='$SELF' param1=unload param2=$id terminal=false refresh=true"
  else
    echo "○ $id"
    echo "--Cargar | bash='$SELF' param1=load param2=$id terminal=false refresh=true"
  fi
done <<< "$ALL"
echo "---"
echo "Reiniciar router | bash='$SELF' param1=restart terminal=false refresh=true"
echo "Detener router | bash='$SELF' param1=stop terminal=false refresh=true"
echo "Ver log | bash=/usr/bin/open param1=-a param2=Console param3=$HOME/Library/Logs/llama-router/out.log terminal=false"
echo "Editar presets | bash=/usr/bin/open param1=-t param2=$HOME/models/presets.ini terminal=false"
echo "Recargar | refresh=true"
