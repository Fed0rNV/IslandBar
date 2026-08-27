#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="$PROJECT_DIR/dist/IslandBar.app"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_DIR/ModuleCache"

mkdir -p "$BUILD_DIR/ModuleCache" "$PROJECT_DIR/dist"

SWIFT_ARGS=(
  -c release
  --disable-sandbox
  --triple arm64-apple-macosx14.0
  --sdk "$SDK_PATH"
  --scratch-path "$BUILD_DIR"
  --cache-path "$BUILD_DIR/cache"
  --config-path "$BUILD_DIR/config"
  --security-path "$BUILD_DIR/security"
  --manifest-cache local
)

swift build "${SWIFT_ARGS[@]}"
BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/IslandBar" "$APP_DIR/Contents/MacOS/IslandBar"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

ICONSET="$BUILD_DIR/IslandBar.iconset"
MASTER_ICON="$BUILD_DIR/IslandBar-1024.png"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swiftc \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK_PATH" \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$PROJECT_DIR/Tools/IconRenderer.swift" \
  -o "$BUILD_DIR/icon-renderer"
"$BUILD_DIR/icon-renderer" "$PROJECT_DIR/IslandBar.svg" "$MASTER_ICON"
sips -z 16 16 "$MASTER_ICON" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$MASTER_ICON" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$MASTER_ICON" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$MASTER_ICON" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$MASTER_ICON" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$MASTER_ICON" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$MASTER_ICON" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$MASTER_ICON" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$MASTER_ICON" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$MASTER_ICON" "$ICONSET/icon_512x512@2x.png"
TIFF_DIR="$BUILD_DIR/IslandBar-tiff"
rm -rf "$TIFF_DIR"
mkdir -p "$TIFF_DIR"
for SIZE in 16 32 128 256 512; do
  sips -s format tiff "$ICONSET/icon_${SIZE}x${SIZE}.png" --out "$TIFF_DIR/$SIZE.tiff" >/dev/null
done
sips -s format tiff "$ICONSET/icon_512x512@2x.png" --out "$TIFF_DIR/1024.tiff" >/dev/null
tiffutil -cat \
  "$TIFF_DIR/16.tiff" "$TIFF_DIR/32.tiff" "$TIFF_DIR/128.tiff" \
  "$TIFF_DIR/256.tiff" "$TIFF_DIR/512.tiff" "$TIFF_DIR/1024.tiff" \
  -out "$BUILD_DIR/IslandBar-multi.tiff" >/dev/null 2>&1
tiff2icns "$BUILD_DIR/IslandBar-multi.tiff" "$APP_DIR/Contents/Resources/IslandBar.icns"

codesign --force --deep --sign - --timestamp=none \
  --entitlements "$PROJECT_DIR/IslandBar.entitlements" "$APP_DIR"

echo "$APP_DIR"
