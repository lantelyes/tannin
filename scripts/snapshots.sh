#!/bin/sh
# Builds the app and has it photograph every one of its screens, in light and dark, into the given folder.
# The app comes to the front while it does this (about half a minute) and then quits.
# The app is started directly, not through "open", so the pictures are taken under the Screen Recording
# permission of the terminal that runs this script.
set -eu
cd "$(dirname "$0")/.."
out="${1:?usage: snapshots.sh <output folder>}"
./scripts/bundle.sh
rm -rf "$out"
mkdir -p "$out"
# Windows left open by an earlier run are not put back: the pictures start from the main window.
TANNIN_SNAPSHOT_DIR="$out" build/Tannin.app/Contents/MacOS/Tannin -ApplePersistenceIgnoreState YES
ls "$out"
