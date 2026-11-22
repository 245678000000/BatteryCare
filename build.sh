#!/bin/bash
# Builds BatteryCare.app (release) into ./dist
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP=dist/BatteryCare.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/BatteryCare" "$APP/Contents/MacOS/BatteryCare"
cp "$BIN/batterycare-helper" "$APP/Contents/Resources/"
cp Resources/*.sh "$APP/Contents/Resources/"

if [ ! -f .build/AppIcon.icns ]; then
  swift Tools/make_icon.swift .build/icon.png
  SET=.build/AppIcon.iconset; rm -rf "$SET"; mkdir -p "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s .build/icon.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) .build/icon.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o .build/AppIcon.icns
fi
cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>电池管家</string>
  <key>CFBundleDisplayName</key><string>电池管家</string>
  <key>CFBundleIdentifier</key><string>com.batterycare.app</string>
  <key>CFBundleExecutable</key><string>BatteryCare</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>电池管家 · 让电池更长寿</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>com.batterycare.app</string>
    <key>CFBundleURLSchemes</key><array><string>batterycare</string></array>
  </dict></array>
</dict></plist>
PL
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"
