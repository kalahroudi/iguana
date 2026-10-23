#!/bin/bash
# Builds Iguana.app into ./dist. Usage: scripts/bundle.sh [version]
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
APP="${DIST_DIR:-dist}/Iguana.app"

swift build -c release --product Iguana
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Iguana" "$APP/Contents/MacOS/Iguana"
strip -x "$APP/Contents/MacOS/Iguana"

ICONSET="$(mktemp -d)/AppIcon.iconset"
"$BIN/Iguana" --write-iconset "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Iguana</string>
  <key>CFBundleDisplayName</key><string>Iguana</string>
  <key>CFBundleIdentifier</key><string>com.kalahroudi.iguana</string>
  <key>CFBundleExecutable</key><string>Iguana</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($(du -sk "$APP" | cut -f1) KB)"
