#!/bin/sh
# Builds build/Tannin.app from the TanninApp target: binary, icon, Info.plist, ad-hoc signature.
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product TanninApp

app="build/Tannin.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/TanninApp "$app/Contents/MacOS/Tannin"

# Icon: one 1024 px drawing, scaled into every size macOS asks for.
iconset="build/AppIcon.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
swift scripts/make-icon.swift build/icon-1024.png
for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z "$size" "$size" build/icon-1024.png --out "$iconset/icon_${size}x${size}.png" > /dev/null
  sips -z "$double" "$double" build/icon-1024.png --out "$iconset/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Tannin</string>
  <key>CFBundleDisplayName</key><string>Tannin</string>
  <key>CFBundleIdentifier</key><string>local.tannin.Tannin</string>
  <key>CFBundleExecutable</key><string>Tannin</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign -f -s - "$app" > /dev/null 2>&1
echo "built $app"
