#!/bin/sh
# Makes a release of Tannin on this Mac: builds and signs it, writes the update feed and the website's
# notes, and, after a typed "yes", publishes them.
#
#   scripts/release.sh <version>                      the real thing; asks for a typed "yes" before publishing
#   scripts/release.sh <version> --dry-run            everything up to the "yes", written into
#                                                     build/release-dry-run/; changes nothing in the repository
#                                                     and publishes nothing
#   scripts/release.sh <version> --confirm <version>  the real thing with the "yes" given beforehand, by writing
#                                                     the version a second time. For a release the owner has
#                                                     asked for in so many words while away from this Mac.
#                                                     Every check below still applies.
#
# A real release refuses to start unless everything it depends on is in place. A dry run lists the same
# refusals and carries on, so the rest can still be looked at.
#
# The order of publishing matters. The download goes up first and is fetched back and compared; only then
# is main pushed, which is what puts the feed on the website and so offers the update to everyone.
set -eu
cd "$(dirname "$0")/.."

version="${1:?usage: release.sh <version> [--dry-run]}"
dry=""
confirmed=""
case "${2:-}" in
  "") ;;
  --dry-run) dry=1 ;;
  --confirm)
    # The version has to be written out again, so that this cannot be a leftover from another release.
    [ "${3:-}" = "$version" ] || { echo "--confirm has to repeat the version: --confirm $version"; exit 2; }
    confirmed=1 ;;
  *) echo "usage: release.sh <version> [--dry-run | --confirm <version>]"; exit 2 ;;
esac

repo="lantelyes/tannin"
site="https://lantelyes.github.io/tannin"
certificate="Tannin Local Signing"
sparkle=".build/artifacts/sparkle/Sparkle/bin"
tag="v$version"
zip="dist/Tannin-$version.zip"
download="https://github.com/$repo/releases/download/$tag/Tannin-$version.zip"
# The feed address is the one built into bundle.sh, never one left over in the environment from a test.
unset TANNIN_FEED_URL

# ---- 1. Is everything in place? ----

problems=0
problem() {
  problems=$((problems + 1))
  if [ -n "$dry" ]; then echo "  would refuse: $1"; else echo "  refusing: $1"; fi
}

echo "Checking that a release of $version can be made"
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "not a version: $version"; exit 2; }

[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || problem "not on the main branch"
[ -z "$(git status --porcelain)" ] || problem "there are changes that have not been committed"
git fetch --quiet origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || problem "main here and main on GitHub differ; push or pull first"
git config user.email | grep -q '@users.noreply.github.com$' || problem "this repository's git email is not the private GitHub address"
[ "$(tr -d '[:space:]' < VERSION)" = "$version" ] || problem "the VERSION file says $(tr -d '[:space:]' < VERSION), not $version"
swift scripts/make-notes.swift check "$version" || problem "CHANGELOG.md has no notes for $version"
if git rev-parse -q --verify "refs/tags/$tag" > /dev/null || [ -n "$(git ls-remote --tags origin "$tag")" ]; then
  problem "the tag $tag already exists"
fi
gh api "repos/$repo/pages" > /dev/null 2>&1 || problem "the website is not turned on (GitHub Pages), so the feed would never go live"

public_key="$(sed -n 's/^public_key="\(.*\)"$/\1/p' scripts/bundle.sh)"
have_key=""
if [ -z "$public_key" ]; then
  problem "scripts/bundle.sh has no update key yet"
elif [ "$("$sparkle/generate_keys" -p 2> /dev/null || true)" != "$public_key" ]; then
  problem "the update key in this Mac's Keychain is missing or is not the one in scripts/bundle.sh"
else
  have_key=1
fi

have_certificate=""
if security find-identity -p codesigning | grep -q "\"$certificate\""; then
  have_certificate=1
else
  problem "the certificate \"$certificate\" is not in this Mac's Keychain"
fi

echo "Running the tests"
mkdir -p build
swift test > build/release-tests.log 2>&1 || problem "the tests fail (see build/release-tests.log)"

if [ "$problems" -gt 0 ] && [ -z "$dry" ]; then
  echo "Not releasing: $problems thing(s) to put right first."
  exit 1
fi

# ---- 2. Build, zip and sign ----

identity="-"
[ -n "$have_certificate" ] && identity="$certificate"
echo "Building Tannin $version, signed with: $identity"
TANNIN_VERSION="$version" TANNIN_SIGN_IDENTITY="$identity" ./scripts/package.sh > /dev/null
[ -f "$zip" ] || { echo "no $zip after packaging"; exit 1; }

if [ -n "$have_certificate" ]; then
  # Updates keep their permissions only if every release answers to the same certificate.
  leaf="$(security find-certificate -c "$certificate" -Z | awk '/SHA-1/ { print tolower($NF) }')"
  codesign -d -r- build/Tannin.app 2>&1 | grep -qi "certificate leaf = H\"$leaf\"" \
    || { echo "the app's signature does not name the certificate \"$certificate\""; exit 1; }
fi

if [ -n "$have_key" ]; then
  signature="$("$sparkle/sign_update" -p "$zip")"
  "$sparkle/sign_update" --verify "$zip" "$signature" > /dev/null
else
  signature="NOT-SIGNED-DRY-RUN"
fi
length="$(stat -f %z "$zip")"
sha256="$(shasum -a 256 "$zip" | cut -d ' ' -f 1)"

# ---- 3. The feed, the notes and the Download button ----

docs="docs"
changelog="CHANGELOG.md"
if [ -n "$dry" ]; then
  rm -rf build/release-dry-run
  mkdir -p build/release-dry-run
  cp -R docs build/release-dry-run/docs
  cp CHANGELOG.md build/release-dry-run/CHANGELOG.md
  docs="build/release-dry-run/docs"
  changelog="build/release-dry-run/CHANGELOG.md"
fi

swift scripts/make-notes.swift stamp "$version" "$(LC_ALL=C date '+%-d %B %Y')" --changelog "$changelog" > /dev/null
swift scripts/make-notes.swift site --changelog "$changelog" --docs "$docs" > /dev/null
swift scripts/make-notes.swift text "$version" --changelog "$changelog" > build/release-notes.md

cat > "$docs/appcast.xml" <<FEED
<?xml version="1.0" encoding="utf-8"?>
<!-- Written by scripts/release.sh. Tannin reads this to learn whether a newer version exists. -->
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Tannin</title>
    <link>$site/</link>
    <description>Updates for Tannin.</description>
    <language>en</language>
    <item>
      <title>Tannin $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <sparkle:releaseNotesLink>$site/notes/$version.html</sparkle:releaseNotesLink>
      <enclosure url="$download" length="$length" type="application/octet-stream" sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
FEED
xmllint --noout "$docs/appcast.xml"

sed -i '' -E "s#releases/download/v[0-9.]+/Tannin-[0-9.]+\\.zip\">Download Tannin [0-9.]+<#releases/download/$tag/Tannin-$version.zip\">Download Tannin $version<#" "$docs/index.html"
grep -q "Tannin-$version.zip\">Download Tannin $version<" "$docs/index.html" \
  || { echo "could not rewrite the Download button in $docs/index.html"; exit 1; }
[ -f "$docs/notes/$version.html" ] || { echo "no notes page was written for $version"; exit 1; }

# ---- 4. Show it, and stop ----

echo
echo "Ready to publish Tannin $version"
echo "  download   $zip ($length bytes)"
echo "  sha-256    $sha256"
echo "  signed by  $identity"
echo "  update key $([ -n "$have_key" ] && echo "signature made and checked" || echo "NOT SIGNED")"
echo "  feed       $docs/appcast.xml  ->  $site/appcast.xml"
echo "  notes      $docs/notes/$version.html, $docs/whats-new.html"
echo "  GitHub     $tag, marked as a pre-release, with this text:"
sed 's/^/      /' build/release-notes.md
echo

if [ -n "$dry" ]; then
  echo "Dry run finished. Nothing was published and the repository was not changed."
  [ "$problems" -gt 0 ] && echo "A real release would have refused: $problems thing(s) listed at the top."
  exit 0
fi

if [ -n "$confirmed" ]; then
  echo "Publishing without asking again: --confirm $version was given."
  answer="yes"
else
  printf 'Publish this to GitHub and to everyone who has Tannin? Type yes: '
  # Only a person at a terminal can answer. Run from anything else, this counts as "no".
  answer=""
  read -r answer < /dev/tty 2> /dev/null || answer=""
fi
if [ "$answer" != "yes" ]; then
  git restore CHANGELOG.md docs
  git clean -fdq docs
  echo "Stopped. Nothing was published; the changelog and the website files are back as they were."
  exit 1
fi

# ---- 5. The download ----

git add CHANGELOG.md docs
git commit --quiet -m "Release $version"
git tag -a "$tag" -m "Tannin $version"
git push --quiet origin "$tag"
gh release create "$tag" "$zip" "$zip.sha256" --repo "$repo" --prerelease --verify-tag \
  --title "Tannin $version (test build)" --notes-file build/release-notes.md

echo "Fetching the download back, the way anyone would"
curl -fsSL -o build/release-check.zip "$download"
if [ "$(shasum -a 256 build/release-check.zip | cut -d ' ' -f 1)" != "$sha256" ]; then
  echo "The file on GitHub is not the file that was built. The feed has NOT been published; nobody is offered this update."
  echo "Look at the release at https://github.com/$repo/releases/tag/$tag before doing anything else."
  exit 1
fi
rm -f build/release-check.zip

# ---- 6. The feed and the website ----

git push --quiet origin main
echo "Waiting for the website to show $version"
tries=0
until curl -fsS "$site/appcast.xml" 2> /dev/null | grep -q "<sparkle:version>$version<"; do
  tries=$((tries + 1))
  if [ "$tries" -ge 60 ]; then
    echo "The feed at $site/appcast.xml still does not show $version after ten minutes."
    echo "The release and the push went through; check the Pages deployment on GitHub."
    exit 1
  fi
  sleep 10
done
echo "Tannin $version is published: https://github.com/$repo/releases/tag/$tag"
