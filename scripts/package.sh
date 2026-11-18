#!/bin/sh
# Builds Tannin.app and zips it for a release: dist/Tannin-<version>.zip, with its SHA-256 beside it.
# The app carries an ad-hoc signature only, so people who download it have to allow it once in
# System Settings > Privacy & Security (see README.md).
set -eu
cd "$(dirname "$0")/.."

./scripts/bundle.sh
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/Tannin.app/Contents/Info.plist)
codesign --verify --strict build/Tannin.app

mkdir -p dist
zip="dist/Tannin-$version.zip"
rm -f "$zip" "$zip.sha256"
# ditto keeps the signature and extended attributes intact, which a plain zip does not always do.
ditto -c -k --keepParent build/Tannin.app "$zip"
(cd dist && shasum -a 256 "Tannin-$version.zip" > "Tannin-$version.zip.sha256")

echo "packaged $zip"
cat "$zip.sha256"
