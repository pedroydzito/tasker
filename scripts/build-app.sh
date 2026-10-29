#!/usr/bin/env bash
# Compila o Tasker e monta o bundle Tasker.app em ./build.
# Uso: scripts/build-app.sh [--install]
# BUILD_NUMBER (opcional) define a versão 0.1.<BUILD_NUMBER>; sem ele o build é "0" (local,
# e o atualizador automático não substitui builds locais).
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD_NUMBER="${BUILD_NUMBER:-0}"
VERSION="0.1.${BUILD_NUMBER}"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Tasker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Tasker" "$APP/Contents/MacOS/Tasker"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources/Fonts"
cp Resources/Fonts/*.ttf Resources/Fonts/*.txt "$APP/Contents/Resources/Fonts/"
# Ícone: o próprio binário desenha a arte em 1024px; geramos todos os tamanhos do .icns.
ICON_PNG="build/icon-1024.png"
if "$BIN_DIR/Tasker" --export-icon "$ICON_PNG"; then
    ICONSET="build/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z $size $size "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double "$ICON_PNG" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    echo "✓ ícone gerado"
else
    echo "⚠︎ não foi possível gerar o ícone; seguindo sem .icns"
fi
# Interface: o mesmo build da web, servido de dentro do app (funciona sem internet).
if [[ -d web/dist ]]; then
    cp -R web/dist "$APP/Contents/Resources/web"
    rm -f "$APP/Contents/Resources/web/sw.js"
    echo "✓ interface web embutida"
else
    echo "⚠︎ web/dist não existe (rode npm run build em web/); seguindo com a interface nativa"
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "✓ $APP ($VERSION)"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Tasker 2>/dev/null || true
    rm -rf /Applications/Tasker.app
    cp -R "$APP" /Applications/
    open /Applications/Tasker.app
    echo "✓ instalado em /Applications/Tasker.app"
fi
