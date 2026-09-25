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
  --exclude='dist' --exclude='.claude' --exclude='.vscode' \
  --exclude='platform.local.txt' \
  --exclude='tools/package' \
  --exclude='*.o' --exclude='*.elf' --exclude='*.bin' --exclude='*.fs' \
  --exclude='build' --exclude='__pycache__' \
  -C "$ROOT" . \
  | tar -x -C "$BOARD_STAGE/arduino-tangnano20k"
tar -cjf "$DIST/$BOARD_ARCHIVE" -C "$BOARD_STAGE" arduino-tangnano20k

RELEASE_URL="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}"

# The RISC-V toolchain only changes with the Zephyr SDK, so it doesn't have
# to be repackaged for every release: without $ZEPHYR_SDK_DIR, the index's
# existing ${TOOL_NAME} ${TOOLCHAIN_VERSION} entry (whose archives stay on
# the release that first published them) is kept as it is.
TOOL_SYSTEMS_JSON=""
if [ -d "$ZEPHYR_SDK_DIR/riscv64-zephyr-elf" ]; then
  echo "== Packaging RISC-V toolchain ($TOOL_ARCHIVE) =="
  rm -f "$DIST/$TOOL_ARCHIVE"
  tar -cjf "$DIST/$TOOL_ARCHIVE" -C "$ZEPHYR_SDK_DIR" riscv64-zephyr-elf
  # Linux x86_64, built above, plus the macOS/Windows archives from
  # tools/package/fetch_zephyr_toolchains.sh (downloaded/repackaged from
  # Zephyr's own prebuilt releases) when dist/toolchains_manifest.tsv
  # exists - see docs/RELEASING.md.
  printf '%s\t%s\t%s\t%s\n' "$HOST" "$TOOL_ARCHIVE" \
    "$(sha256sum "$DIST/$TOOL_ARCHIVE" | cut -d' ' -f1)" \
    "$(stat --format=%s "$DIST/$TOOL_ARCHIVE")" > "$DIST/toolchain_linux_manifest.tsv"
  TOOL_SYSTEMS_JSON="$(python3 "$ROOT/tools/package/manifest_systems.py" "$RELEASE_URL" \
    "$DIST/toolchain_linux_manifest.tsv" "$DIST/toolchains_manifest.tsv")"
  rm -f "$DIST/toolchain_linux_manifest.tsv"
else
  echo "== $ZEPHYR_SDK_DIR/riscv64-zephyr-elf not found - keeping the index's ${TOOL_NAME} ${TOOLCHAIN_VERSION} entry =="
fi

# FPGA tools (yosys, nextpnr-himbaechel, gowin_pack, openFPGALoader): the
# archives tools/package/make_fpga_tools.py builds, listed in
# dist/fpga_tools_manifest.tsv. Without it, the index's existing entry for
# the version platform.txt pins is kept as it is.
FPGA_TOOL_NAME="oss-cad-suite-gowin"
FPGA_TOOL_VERSION="$(sed -n 's/^fpga_tools.path={runtime.tools.'"$FPGA_TOOL_NAME"'-\(.*\).path}$/\1/p' platform.txt)"
[ -n "$FPGA_TOOL_VERSION" ] || { echo "ERROR: no fpga_tools.path line in platform.txt" >&2; exit 1; }
FPGA_SYSTEMS_JSON=""
if [ -f "$DIST/fpga_tools_manifest.tsv" ]; then
  echo "== Merging dist/fpga_tools_manifest.tsv ($FPGA_TOOL_NAME $FPGA_TOOL_VERSION) =="
  FPGA_SYSTEMS_JSON="$(python3 "$ROOT/tools/package/manifest_systems.py" "$RELEASE_URL" \
    "$DIST/fpga_tools_manifest.tsv")"
fi

board_sha=$(sha256sum "$DIST/$BOARD_ARCHIVE" | cut -d' ' -f1)
board_size=$(stat --format=%s "$DIST/$BOARD_ARCHIVE")

echo "== Writing package_nanotang_index.json =="
python3 - "$ROOT/package_nanotang_index.json" "$TOOL_SYSTEMS_JSON" "$FPGA_SYSTEMS_JSON" <<PYEOF
import json, os, sys

path = sys.argv[1]
tool_systems, fpga_systems = sys.argv[2], sys.argv[3]

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
        {"packager": "nanotang", "name": "${TOOL_NAME}", "version": "${TOOLCHAIN_VERSION}"},
        {"packager": "nanotang", "name": "${FPGA_TOOL_NAME}", "version": "${FPGA_TOOL_VERSION}"},
    ]
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

tools = package.setdefault("tools", [])
for dep in new_platform["toolsDependencies"]:
    systems = tool_systems if dep["name"] == "${TOOL_NAME}" else fpga_systems
    existing = [t for t in tools if t["name"] == dep["name"] and t["version"] == dep["version"]]
    if systems:
        tools[:] = [t for t in tools if t not in existing]
        tools.append({"name": dep["name"], "version": dep["version"], "systems": json.loads(systems)})
    elif not existing:
        sys.exit(f"ERROR: {dep['name']} {dep['version']} is neither in the index nor built "
                 "into dist/ - see docs/RELEASING.md")
tools.sort(key=lambda t: (t["name"], t["version"]))

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
