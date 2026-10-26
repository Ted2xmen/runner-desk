#!/bin/sh
# Copies the gate's Debug build to ~/Applications/Runner Desk.app and opens it.
# The build product in DerivedData is unregistered from Launch Services afterwards, so
# runnerdesk:// links always open the installed copy, never a stale build.
set -eu

BUILD="$HOME/Library/Caches/runner-desk-dd/Build/Products/Debug/Runner Desk.app"
DEST="$HOME/Applications/Runner Desk.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

[ -d "$BUILD" ] || { echo "No build at $BUILD; run scripts/gate.sh first." >&2; exit 1; }

# Quit only the copy running from the installed path.
for pid in $(pgrep -f "$DEST/Contents/MacOS/Runner Desk" || true); do kill -TERM "$pid"; done
sleep 1

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$BUILD" "$DEST"
"$LSREGISTER" -f "$DEST"
"$LSREGISTER" -u "$BUILD" || true

open "$DEST"
echo "$DEST"
