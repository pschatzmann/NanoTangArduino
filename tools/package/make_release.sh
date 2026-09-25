#!/usr/bin/env bash
# Builds the two release archives (board package + RISC-V toolchain) and
# regenerates package_nanotang_index.json with real checksums/sizes, ready
# to attach to a GitHub Release - see docs/RELEASING.md for the full
# process this is one step of. Does not push or publish anything itself.
#
# Usage:
#   tools/package/make_release.sh [version]
#     version defaults to platform.txt's version= line.
#
# Env overrides:
#   ZEPHYR_SDK_DIR   - path to the Zephyr SDK (default: ~/zephyr-sdk-0.17.0)
#   TOOLCHAIN_VERSION - the riscv-zephyr-elf tool's own version string in
#                        the index (default: the Zephyr SDK's own version,
#                        read from $ZEPHYR_SDK_DIR/sdk_version)
#   GITHUB_REPO      - owner/repo used to build the release download URLs
#                        (default: pschatzmann/arduino-tangnano20k)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(sed -n 's/^version=//p' platform.txt)}"
ZEPHYR_SDK_DIR="${ZEPHYR_SDK_DIR:-$HOME/zephyr-sdk-0.17.0}"
TOOLCHAIN_VERSION="${TOOLCHAIN_VERSION:-$(cat "$ZEPHYR_SDK_DIR/sdk_version" 2>/dev/null || echo "0.17.0")}"
GITHUB_REPO="${GITHUB_REPO:-pschatzmann/arduino-tangnano20k}"
HOST="x86_64-pc-linux-gnu"

BOARD_ARCHIVE="arduino-tangnano20k-${VERSION}.tar.bz2"
TOOL_NAME="riscv-zephyr-elf"
TOOL_ARCHIVE="${TOOL_NAME}-${TOOLCHAIN_VERSION}-${HOST}.tar.bz2"

DIST="$ROOT/dist"
# Deliberately not `rm -rf "$DIST"` - tools/package/fetch_zephyr_toolchains.sh
# may have already populated it with macOS/Windows toolchain archives plus
# dist/toolchains_manifest.tsv (see below); wiping the directory here would
# silently discard that work. Only the two files this script itself
# produces are removed/overwritten below.
mkdir -p "$DIST"
rm -f "$DIST/$BOARD_ARCHIVE" "$DIST/$TOOL_ARCHIVE"

echo "== Packaging board files ($BOARD_ARCHIVE) =="
BOARD_STAGE="$(mktemp -d)"
trap 'rm -rf "$BOARD_STAGE"' EXIT
mkdir -p "$BOARD_STAGE/arduino-tangnano20k"
tar -c \
  --exclude='.git*' \
  --exclude='.github' \
  --exclude='ArduinoCore-API' \
  --exclude='dist' \
  --exclude='platform.local.txt' \
  --exclude='tools/package' \
  --exclude='*.o' --exclude='*.elf' --exclude='*.bin' --exclude='*.fs' \
  --exclude='build' --exclude='__pycache__' \
  -C "$ROOT" . \
  | tar -x -C "$BOARD_STAGE/arduino-tangnano20k"
tar -cjf "$DIST/$BOARD_ARCHIVE" -C "$BOARD_STAGE" arduino-tangnano20k

echo "== Packaging RISC-V toolchain ($TOOL_ARCHIVE) =="
if [ ! -d "$ZEPHYR_SDK_DIR/riscv64-zephyr-elf" ]; then
  echo "ERROR: $ZEPHYR_SDK_DIR/riscv64-zephyr-elf not found - set ZEPHYR_SDK_DIR" >&2
  exit 1
fi
tar -cjf "$DIST/$TOOL_ARCHIVE" -C "$ZEPHYR_SDK_DIR" riscv64-zephyr-elf

echo "== Computing checksums/sizes =="
board_sha=$(sha256sum "$DIST/$BOARD_ARCHIVE" | cut -d' ' -f1)
board_size=$(stat --format=%s "$DIST/$BOARD_ARCHIVE")
tool_sha=$(sha256sum "$DIST/$TOOL_ARCHIVE" | cut -d' ' -f1)
tool_size=$(stat --format=%s "$DIST/$TOOL_ARCHIVE")

RELEASE_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}"

# macOS/Windows toolchain archives are optional and produced separately by
# tools/package/fetch_zephyr_toolchains.sh (they're downloaded/repackaged
# from Zephyr's own prebuilt releases, not built on this machine) - see
# docs/RELEASING.md. When dist/toolchains_manifest.tsv exists (that
# script's output: host<TAB>archiveFileName<TAB>sha256<TAB>size per line),
# merge those hosts in as additional tools[].systems entries alongside the
# Linux x86_64 one built above; otherwise the index stays Linux-only, same
# as before this script existed.
EXTRA_SYSTEMS_JSON="[]"
if [ -f "$DIST/toolchains_manifest.tsv" ]; then
  echo "== Merging dist/toolchains_manifest.tsv (macOS/Windows toolchains) =="
  EXTRA_SYSTEMS_JSON="$(python3 - "$DIST/toolchains_manifest.tsv" "$RELEASE_URL" <<'PYEOF'
import csv, json, sys

manifest_path, release_url = sys.argv[1], sys.argv[2]
systems = []
with open(manifest_path, newline="") as f:
    for host, archive, sha, size in csv.reader(f, delimiter="\t"):
        systems.append({
            "host": host,
            "url": f"{release_url}/{archive}",
            "archiveFileName": archive,
            "checksum": f"SHA-256:{sha}",
            "size": size,
        })
print(json.dumps(systems))
PYEOF
)"
fi

echo "== Writing package_nanotang_index.json =="
python3 - "$ROOT/package_nanotang_index.json" "$EXTRA_SYSTEMS_JSON" <<PYEOF
import json, os, sys

path = sys.argv[1]
extra_systems = json.loads(sys.argv[2])

new_platform = {
    "name": "Sipeed Tang Nano 20K (PicoRV32 SoC)",
    "architecture": "tangnano20k",
    "version": "${VERSION}",
    "category": "Contributed",
    "url": "${RELEASE_URL}/${BOARD_ARCHIVE}",
    "archiveFileName": "${BOARD_ARCHIVE}",
    "checksum": "SHA-256:${board_sha}",
    "size": "${board_size}",
    "help": {"online": "https://github.com/${GITHUB_REPO}/blob/main/docs/BUILDING.md"},
    "boards": [{"name": "Tang Nano 20K (PicoRV32 SoC)"}],
    "toolsDependencies": [
        {"packager": "nanotang", "name": "${TOOL_NAME}", "version": "${TOOLCHAIN_VERSION}"}
    ]
}
new_tool = {
    "name": "${TOOL_NAME}",
    "version": "${TOOLCHAIN_VERSION}",
    "systems": [{
        "host": "${HOST}",
        "url": "${RELEASE_URL}/${TOOL_ARCHIVE}",
        "archiveFileName": "${TOOL_ARCHIVE}",
        "checksum": "SHA-256:${tool_sha}",
        "size": "${tool_size}"
    }] + extra_systems
}

# Merge into the existing index (if any) instead of overwriting it, so
# previously released versions stay listed in Arduino Board Manager - each
# release only ever adds/updates its own version's entry.
if os.path.exists(path):
    with open(path) as f:
        index = json.load(f)
else:
    index = {"packages": [{
        "name": "nanotang",
        "maintainer": "Phil Schatzmann",
        "websiteURL": "https://github.com/${GITHUB_REPO}",
        "email": "phil.schatzmann@gmail.com",
        "help": {"online": "https://github.com/${GITHUB_REPO}/blob/main/docs/BUILDING.md"},
        "platforms": [],
        "tools": [],
    }]}

package = index["packages"][0]

platforms = [p for p in package.get("platforms", []) if p.get("version") != "${VERSION}"]
platforms.append(new_platform)
platforms.sort(key=lambda p: tuple(int(x) for x in p["version"].split(".")))
package["platforms"] = platforms

tools = [t for t in package.get("tools", []) if t.get("version") != "${TOOLCHAIN_VERSION}"]
tools.append(new_tool)
tools.sort(key=lambda t: t["version"])
package["tools"] = tools

with open(path, "w") as f:
    json.dump(index, f, indent=2)
    f.write("\n")
print(f"Wrote {path} ({len(platforms)} platform version(s), {len(tools)} tool version(s))")
PYEOF

echo
echo "Done. dist/:"
ls -la "$DIST"
echo
echo "Next: create a GitHub Release tagged v${VERSION} on ${GITHUB_REPO}"
echo "and attach both files under dist/ - see docs/RELEASING.md."
