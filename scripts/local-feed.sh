#!/bin/sh
# For testing updates on this Mac only: offers one test version of Tannin from http://localhost:8765/.
#
#   scripts/local-feed.sh <version>     build and sign that version, write build/local-feed/, and serve it
#
# The test build's feed address is the local one, so it never looks at the real website. Install an older
# test build first (made the same way, or by this script with a lower version), then run this with a higher
# version and choose Tannin > Check for Updates… . Stop the server with Control-C.
# Needs the update key and the "Tannin Local Signing" certificate in the Keychain.
set -eu
cd "$(dirname "$0")/.."

version="${1:?usage: local-feed.sh <version>}"
port=8765
feed="build/local-feed"
sparkle=".build/artifacts/sparkle/Sparkle/bin"

TANNIN_VERSION="$version" TANNIN_SIGN_IDENTITY="Tannin Local Signing" \
  TANNIN_FEED_URL="http://localhost:$port/appcast.xml" ./scripts/package.sh > /dev/null

mkdir -p "$feed/notes"
cp "dist/Tannin-$version.zip" "$feed/"
signature="$("$sparkle/sign_update" -p "$feed/Tannin-$version.zip")"
length="$(stat -f %z "$feed/Tannin-$version.zip")"

cat > "$feed/notes/$version.html" <<NOTES
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="color-scheme" content="light dark">
<style>body { margin: 0; padding: 10px 14px; font: 12px/17px -apple-system, sans-serif; }</style></head>
<body><b>New in $version</b><ul><li>A test update, served from this Mac.</li></ul></body></html>
NOTES

cat > "$feed/appcast.xml" <<FEED
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Tannin (local test)</title>
    <item>
      <title>Tannin $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <sparkle:releaseNotesLink>http://localhost:$port/notes/$version.html</sparkle:releaseNotesLink>
      <enclosure url="http://localhost:$port/Tannin-$version.zip" length="$length" type="application/octet-stream" sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
FEED

echo "Offering Tannin $version at http://localhost:$port/appcast.xml (this Mac only). Control-C stops it."
exec python3 -m http.server "$port" --bind 127.0.0.1 --directory "$feed"
