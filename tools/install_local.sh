#!/usr/bin/env bash
# Copies this checkout over the Boards Manager installation of the core
# (<data dir>/packages/nanotang/hardware/tangnano20k/<version>), so the
# Arduino IDE and arduino-cli use the working tree without a release.
# Copies the same files the release archive contains (see
# tools/package/make_release.sh), and removes installed files that no
# longer exist here - except installed.json (Boards Manager's own record)
# and platform.local.txt (local overrides), which are left alone.
#
# Usage:
#   tools/install_local.sh [-n] [version]
#     -n       dry run: only list what would change
#     version  installed version directory to overwrite; defaults to the
#              only one present
#
# The Arduino IDE 2 caches each board's Tools menus per core version in
# ~/.config/arduino-ide/"Local Storage", so under an unchanged version it
# keeps showing the old menus. The script therefore deletes that folder
# too (it also holds a few other IDE UI settings, e.g. recent boards) -
# but only while the IDE isn't running, since a running IDE writes it
# back; quit the IDE first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

DRY_RUN=()
if [ "${1:-}" = "-n" ]; then
  DRY_RUN=(--dry-run)
  shift
fi

DATA_DIR="$(arduino-cli config get directories.data 2>/dev/null || true)"
[ -n "$DATA_DIR" ] || DATA_DIR="$HOME/.arduino15"
BASE="$DATA_DIR/packages/nanotang/hardware/tangnano20k"

if [ $# -ge 1 ]; then
  VERSION="$1"
else
  mapfile -t versions < <(ls "$BASE" 2>/dev/null)
  if [ "${#versions[@]}" -ne 1 ]; then
    echo "error: expected exactly one installed version in $BASE, found: ${versions[*]:-none}" >&2
    echo "Install the core via Boards Manager first, or pass the version." >&2
    exit 1
  fi
  VERSION="${versions[0]}"
fi

DEST="$BASE/$VERSION"
if [ ! -f "$DEST/platform.txt" ]; then
  echo "error: $DEST is not an installed core (no platform.txt)" >&2
  exit 1
fi

echo "Copying $ROOT -> $DEST"
rsync -a --delete --itemize-changes "${DRY_RUN[@]}" \
  --exclude='.git*' \
  --exclude='.github' \
  --exclude='.claude' \
  --exclude='.vscode' \
  --exclude='ArduinoCore-API' \
  --exclude='dist' \
  --exclude='tools/package' \
  --exclude='__pycache__' \
  --exclude='*.o' --exclude='*.elf' --exclude='*.bin' --exclude='*.fs' \
  --exclude='build' \
  --exclude='/installed.json' \
  --exclude='/platform.local.txt' \
  "$ROOT/" "$DEST/"

IDE_CACHE="$HOME/.config/arduino-ide/Local Storage"
if [ ${#DRY_RUN[@]} -ne 0 ]; then
  if [ -d "$IDE_CACHE" ]; then
    echo "Would delete the IDE's menu cache: $IDE_CACHE"
  fi
elif [ ! -d "$IDE_CACHE" ]; then
  echo "Done."
elif pgrep -f "arduino-ide" >/dev/null 2>&1; then
  echo "Done, but the Arduino IDE is running, so its cached Tools menus were not"
  echo "cleared: quit the IDE and run this script again to see menu changes."
else
  rm -rf "$IDE_CACHE"
  echo "Done. Cleared the IDE's cached Tools menus ($IDE_CACHE)."
fi
