#!/bin/sh
# Builds build/Tannin.app from the TanninApp target: binary, Sparkle, icon, Info.plist, signature.
#
#   TANNIN_VERSION        the version to stamp, instead of the VERSION file (test builds)
#   TANNIN_SIGN_IDENTITY  the code-signing identity; "-" (the default) signs for this Mac only
#   TANNIN_FEED_URL       the update feed built into the app, instead of the project's website
#   TANNIN_NO_UPDATES     set to 1 to leave the update feed out: a copy for looking at, which neither
#                         checks for updates nor asks to be moved to Applications
#
# The feed address is fixed when the app is built. Nothing can change it while the app runs.
set -eu
cd "$(dirname "$0")/.."

version="${TANNIN_VERSION:-$(tr -d '[:space:]' < VERSION)}"
identity="${TANNIN_SIGN_IDENTITY:--}"
feed="${TANNIN_FEED_URL:-https://lantelyes.github.io/tannin/appcast.xml}"
# The public half of the key that signs updates. An app only installs an update signed with the
# private half, which stays in the Keychain of the Mac that makes releases. While this is empty the
# app is built without updating: no feed, and "Check for Updates…" stays disabled.
public_key="4nZIWy/UFPuPllIeBGV3upSKi+462cOd8anyKoX0EVs="

swift build -c release --product TanninApp
products="$(swift build -c release --show-bin-path)"

app="build/Tannin.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$products/TanninApp" "$app/Contents/MacOS/Tannin"

# Sparkle, as its authors ship it: ditto keeps the framework's symbolic links and its own signature.
ditto "$products/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/Tannin" 2> /dev/null
cp .build/checkouts/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE.txt"
# The package manager keeps its checkouts read-only. A read-only file inside the app cannot have the
# mark macOS puts on downloads taken off it, which moving the app to Applications needs to do.
chmod -R u+w "$app"

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

updates=""
if [ -n "$public_key" ] && [ "${TANNIN_NO_UPDATES:-}" != "1" ]; then
  # Check once a day, and always ask before installing.
  updates="  <key>SUFeedURL</key><string>$feed</string>
  <key>SUPublicEDKey</key><string>$public_key</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>SUAllowsAutomaticUpdates</key><false/>"
  case "$feed" in
    http://localhost*)
      # A test feed served from this Mac. macOS refuses plain http unless the app says local addresses are fine.
      updates="$updates
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>" ;;
  esac
fi

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Tannin</string>
  <key>CFBundleDisplayName</key><string>Tannin</string>
  <key>CFBundleIdentifier</key><string>io.github.lantelyes.Tannin</string>
  <key>CFBundleExecutable</key><string>Tannin</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
$updates
</dict>
</plist>
PLIST
plutil -lint "$app/Contents/Info.plist" > /dev/null

# The app is signed last and on its own: Sparkle keeps the signature it shipped with. No hardened
# runtime, because without an Apple team it would stop the app loading Sparkle.
codesign --force --sign "$identity" "$app"
codesign --verify --deep --strict "$app"

if [ "${TANNIN_NO_UPDATES:-}" = "1" ]; then
  echo "built $app $version (updating is off: TANNIN_NO_UPDATES=1)"
elif [ -n "$public_key" ]; then
  echo "built $app $version (updates from $feed)"
else
  echo "built $app $version (updating is off: no update key in scripts/bundle.sh yet)"
fi
