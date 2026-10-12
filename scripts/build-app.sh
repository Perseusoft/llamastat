#!/bin/bash
# Compila en release y arma build/Llamastat.app. Con --install la copia a ~/Applications y la abre.
set -e
cd "$(dirname "$0")/.."

# Los macros de SwiftUI (@State, @Observable) vienen con Xcode, no con Command Line Tools.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

swift build -c release
APP="build/Llamastat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/bin/cp "$(swift build -c release --show-bin-path)/Llamastat" "$APP/Contents/MacOS/"
/bin/cp Resources/Info.plist "$APP/Contents/"
/bin/cp -R Resources/*.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "==> $APP"

if [ "$1" = "--install" ]; then
  pkill -x Llamastat 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Llamastat.app"
  /bin/cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/Llamastat.app"
  echo "==> instalada en ~/Applications y abierta"
fi
