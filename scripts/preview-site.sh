#!/bin/sh
# Shows the website as the next release would publish it, served from this Mac only.
#
# Copies docs/ and CHANGELOG.md into build/site-preview/, dates a version that is not released yet with
# today's date there, writes the What's New page and the update window's notes from that copy, points
# the Download button at the version in VERSION, and serves the folder until Control-C.
# Nothing in the repository changes and nothing is published.
#
#   scripts/preview-site.sh            serve on http://127.0.0.1:8766/ and open it in the browser
#   TANNIN_PREVIEW_PORT=9000 …         another port
#   TANNIN_PREVIEW_NO_OPEN=1 …         do not open the browser
set -eu
cd "$(dirname "$0")/.."

version="$(tr -d '[:space:]' < VERSION)"
port="${TANNIN_PREVIEW_PORT:-8766}"
out="build/site-preview"

rm -rf "$out"
mkdir -p "$out"
cp -R docs "$out/docs"
cp CHANGELOG.md "$out/CHANGELOG.md"

swift scripts/make-notes.swift stamp "$version" "$(LC_ALL=C date '+%B %-d, %Y')" --changelog "$out/CHANGELOG.md" > /dev/null
swift scripts/make-notes.swift site --changelog "$out/CHANGELOG.md" --docs "$out/docs" > /dev/null
sed -i '' -E "s#releases/download/v[0-9.]+/Tannin-[0-9.]+\\.zip\">Download Tannin [0-9.]+<#releases/download/v$version/Tannin-$version.zip\">Download Tannin $version<#" "$out/docs/index.html"

url="http://127.0.0.1:$port/"
echo "Tannin $version website preview: $url"
echo "  What's New:            ${url}whats-new.html"
echo "  Update window's notes: ${url}notes/$version.html"
echo "The Download button points at a release that may not exist yet. Control-C stops the preview."
[ "${TANNIN_PREVIEW_NO_OPEN:-}" = "1" ] || (sleep 1; open "$url") &
exec python3 -m http.server "$port" --bind 127.0.0.1 --directory "$out/docs"
