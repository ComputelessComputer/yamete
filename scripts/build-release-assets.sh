#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAG="${1:-v0.0.0-dev}"
OUTPUT_DIR="${2:-$ROOT_DIR/dist}"

APP_NAME="Yamete"
EXECUTABLE_NAME="yamete"
BUNDLE_ID="com.computelesscomputer.yamete"
VERSION="${TAG#v}"
PRODUCT_DIR="$ROOT_DIR/.build/apple/Products/Release"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
DMG_PATH="$OUTPUT_DIR/${APP_NAME}-${TAG}-macos.dmg"
CHECKSUM_PATH="${DMG_PATH}.sha256"

mkdir -p "$OUTPUT_DIR"

echo "Building universal release binary..."
swift build -c release --arch arm64 --arch x86_64

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$PRODUCT_DIR/$EXECUTABLE_NAME" "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"

find "$PRODUCT_DIR" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP_PATH/Contents/Resources/" \;

cat > "$APP_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.entertainment</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

DMG_STAGING="$(mktemp -d)"
cleanup() {
  rm -rf "$DMG_STAGING"
}
trap cleanup EXIT

cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG_PATH" "$CHECKSUM_PATH"

echo "Creating DMG..."
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"

echo "App bundle: $APP_PATH"
echo "DMG: $DMG_PATH"
echo "Checksum: $CHECKSUM_PATH"
