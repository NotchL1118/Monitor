#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/ModuleCache"
mkdir -p "$PROJECT_ROOT/.build/ModuleCache"
swift scripts/make-icon.swift "$PROJECT_ROOT/Resources/Brand/app-icon.png"
swiftc Sources/Monitor/MascotArtwork.swift scripts/make-brand-assets.swift -o "$PROJECT_ROOT/.build/make-brand-assets"
"$PROJECT_ROOT/.build/make-brand-assets" "$PROJECT_ROOT"
cp Resources/Brand/app-icon.png ChromeExtension/icons/portrait.png
swift build -c release --disable-sandbox --cache-path "$PROJECT_ROOT/.build/cache"
BIN_DIR="$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$PROJECT_ROOT/.build/cache")"
APP="$PROJECT_ROOT/dist/Monitor.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/ChromeExtension"
cp "$BIN_DIR/Monitor" "$APP/Contents/MacOS/Monitor"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp ChromeExtension/{manifest.json,activity.js,background.js,mascot.js,popup.html,popup.css,popup.js} "$APP/Contents/Resources/ChromeExtension/"
cp -R ChromeExtension/icons "$APP/Contents/Resources/ChromeExtension/"
mkdir -p "$APP/Contents/Resources/Brand"
cp Resources/Brand/app-icon.png "$APP/Contents/Resources/Brand/"
ICONSET="$PROJECT_ROOT/.build/AppIcon.iconset"
mkdir -p "$ICONSET"
cp Resources/Brand/app-icon.png "$PROJECT_ROOT/.build/icon-1024.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$PROJECT_ROOT/.build/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$PROJECT_ROOT/.build/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
# In-place builds only replace nested files. Refresh the bundle timestamp so
# macOS invalidates the previous app icon when the rebuilt app is launched.
touch "$APP"
printf '\nBuilt: %s\nOpen with: open "%s"\n' "$APP" "$APP"
