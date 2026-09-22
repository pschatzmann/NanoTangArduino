#!/usr/bin/env bash
# Downloads the official Zephyr SDK per-host "minimal toolchain" archives
# for riscv64-zephyr-elf (published directly on zephyrproject-rtos/sdk-ng's
# GitHub releases - no need to have macOS/Windows machines to build these,
# since Zephyr already publishes a prebuilt archive per host) and
# repackages each into this project's own naming/format convention, ready
# for tools/package/make_release.sh's index-writing step to pick up.
#
# This is what actually produces the macOS/Windows toolchain archives
# docs/RELEASING.md's "Linux x86_64 only for now" note is waiting on - see
# that file and docs/BUILDING.md.
#
# Usage:
#   tools/package/fetch_zephyr_toolchains.sh [toolchain-version]
#     toolchain-version defaults to reading $ZEPHYR_SDK_DIR/sdk_version
#     (the version of the Zephyr SDK already installed for local Linux
#     builds), so the Linux and non-Linux archives stay in lockstep by
#     default.
#
# Writes one archive per host into dist/, alongside (not replacing) the
# Linux x86_64 archive make_release.sh produces from the local SDK install:
#   riscv-zephyr-elf-<version>-x86_64-apple-darwin.tar.bz2   (macOS Intel)
#   riscv-zephyr-elf-<version>-arm64-apple-darwin.tar.bz2    (macOS Apple Silicon)
#   riscv-zephyr-elf-<version>-x86_64-mingw32.zip            (Windows 64-bit)
#
# Host triples above match what arduino-cli/the Arduino IDE actually look
# for (confirmed against Arduino's own official package_index.json and
# Espressif's package_esp32_index.json, which both ship multi-host GCC
# tools using exactly these strings). Archive formats per host also match
# that precedent: .tar.bz2 for Linux/macOS, .zip for Windows (arduino-cli's
# downloader does not support 7z, which is the format Zephyr publishes the
# Windows toolchain in - this script converts it).
#
# Each download is verified against sdk-ng's own published sha256.sum
# before repackaging - never trust an unverified toolchain binary.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ZEPHYR_SDK_DIR="${ZEPHYR_SDK_DIR:-$HOME/zephyr-sdk-0.17.0}"
TOOLCHAIN_VERSION="${1:-${TOOLCHAIN_VERSION:-$(cat "$ZEPHYR_SDK_DIR/sdk_version" 2>/dev/null || echo "0.17.0")}}"
TOOL_NAME="riscv-zephyr-elf"
SDK_TARBALL_NAME="riscv64-zephyr-elf"
RELEASE_BASE="https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${TOOLCHAIN_VERSION}"

DIST="$ROOT/dist"
mkdir -p "$DIST"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "== Fetching sdk-ng v${TOOLCHAIN_VERSION} checksums =="
curl -sL -o "$WORK/sha256.sum" "$RELEASE_BASE/sha256.sum"

# zephyr_asset  our_archive_name                                    our_host_triple
declare -a SPECS=(
  "toolchain_macos-x86_64_riscv64-zephyr-elf.tar.xz|${TOOL_NAME}-${TOOLCHAIN_VERSION}-x86_64-apple-darwin.tar.bz2|x86_64-apple-darwin"
  "toolchain_macos-aarch64_riscv64-zephyr-elf.tar.xz|${TOOL_NAME}-${TOOLCHAIN_VERSION}-arm64-apple-darwin.tar.bz2|arm64-apple-darwin"
  "toolchain_windows-x86_64_riscv64-zephyr-elf.7z|${TOOL_NAME}-${TOOLCHAIN_VERSION}-x86_64-mingw32.zip|x86_64-mingw32"
)

# host_triple -> checksum:size, written for fetch_zephyr_toolchains_index.json below
: > "$DIST/toolchains_manifest.tsv"

for spec in "${SPECS[@]}"; do
  IFS='|' read -r zephyr_asset our_archive our_host <<< "$spec"

  echo "== $zephyr_asset -> $our_archive =="
  src="$WORK/$zephyr_asset"
  curl -sL -o "$src" "$RELEASE_BASE/$zephyr_asset"

  expected_sha="$(grep " $zephyr_asset\$" "$WORK/sha256.sum" | awk '{print $1}')"
  if [ -z "$expected_sha" ]; then
    echo "ERROR: no checksum found for $zephyr_asset in sha256.sum" >&2
    exit 1
  fi
  actual_sha="$(sha256sum "$src" | awk '{print $1}')"
  if [ "$expected_sha" != "$actual_sha" ]; then
    echo "ERROR: checksum mismatch for $zephyr_asset (expected $expected_sha, got $actual_sha)" >&2
    exit 1
  fi
  echo "   checksum verified against sdk-ng's sha256.sum"

  extract_dir="$WORK/extract-$our_host"
  mkdir -p "$extract_dir"
  case "$zephyr_asset" in
    *.tar.xz)
      tar -xJf "$src" -C "$extract_dir"
      ;;
    *.7z)
      7z x -o"$extract_dir" "$src" > /dev/null
      ;;
  esac
  if [ ! -d "$extract_dir/$SDK_TARBALL_NAME" ]; then
    echo "ERROR: $zephyr_asset didn't extract to a top-level $SDK_TARBALL_NAME/ dir as expected" >&2
    exit 1
  fi

  out="$DIST/$our_archive"
  case "$our_archive" in
    *.tar.bz2)
      tar -cjf "$out" -C "$extract_dir" "$SDK_TARBALL_NAME"
      ;;
    *.zip)
      ( cd "$extract_dir" && zip -qr "$out" "$SDK_TARBALL_NAME" )
      ;;
  esac

  out_sha="$(sha256sum "$out" | awk '{print $1}')"
  out_size="$(stat --format=%s "$out")"
  printf '%s\t%s\t%s\t%s\n' "$our_host" "$our_archive" "$out_sha" "$out_size" >> "$DIST/toolchains_manifest.tsv"
  rm -rf "$extract_dir" "$src"
done

echo
echo "Done. Archives written to dist/:"
cat "$DIST/toolchains_manifest.tsv"
echo
echo "Next: pass these through to package_nanotang_index.json - either"
echo "re-run tools/package/make_release.sh (it merges dist/toolchains_manifest.tsv"
echo "into the tool's systems[] automatically when present), or add the"
echo "systems[] entries by hand using the host/archiveFileName/checksum/size"
echo "columns above - see docs/RELEASING.md."
