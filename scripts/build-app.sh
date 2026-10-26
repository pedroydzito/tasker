#!/usr/bin/env bash
# Compila o Tasker e monta o bundle Tasker.app em ./build.
# Uso: scripts/build-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Tasker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Tasker" "$APP/Contents/MacOS/Tasker"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "✓ $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Tasker 2>/dev/null || true
    rm -rf /Applications/Tasker.app
    cp -R "$APP" /Applications/
    open /Applications/Tasker.app
    echo "✓ instalado em /Applications/Tasker.app"
fi
