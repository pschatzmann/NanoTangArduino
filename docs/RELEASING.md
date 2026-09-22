# Releasing

How to cut a release that Arduino Boards Manager users can install via
`package_nanotang_index.json`. See [Building, installing, and
verifying](BUILDING.md#installing-via-boards-manager) for what the
resulting install experience looks like.

## What gets published

The board package plus one toolchain archive per supported host, all
attached to one GitHub Release:

- `NanoTangArduino-<version>.tar.bz2` - the board package itself
  (`boards.txt`, `platform.txt`, `cores/`, `variants/`, `libraries/`,
  `gateware/`, `tools/`, `examples/`, `docs/`).
- `riscv-zephyr-elf-<toolchain-version>-<host-triple>.<ext>` - the Zephyr
  SDK's `riscv64-zephyr-elf` compiler, re-hosted as a Boards Manager
  **tool** dependency so installing the board also installs a working
  compiler with no manual steps (see [Licensing](LICENSING.md) - this is
  an unmodified re-host of Zephyr's own public GCC/binutils build, not a
  licensing complication). One archive per supported host:

  | Host | Archive | Produced by |
  |---|---|---|
  | Linux x86_64 | `...-x86_64-pc-linux-gnu.tar.bz2` | `make_release.sh`, from a local `$ZEPHYR_SDK_DIR` install |
  | macOS Intel | `...-x86_64-apple-darwin.tar.bz2` | `fetch_zephyr_toolchains.sh` |
  | macOS Apple Silicon | `...-arm64-apple-darwin.tar.bz2` | `fetch_zephyr_toolchains.sh` |
  | Windows 64-bit | `...-x86_64-mingw32.zip` | `fetch_zephyr_toolchains.sh` |

  The Linux archive is built from a toolchain actually installed on the
  packaging machine; the other three are downloaded directly from
  [zephyrproject-rtos/sdk-ng's releases](https://github.com/zephyrproject-rtos/sdk-ng/releases)
  (Zephyr already publishes a prebuilt minimal toolchain per host - no
  macOS/Windows machine needed here) and repackaged into this project's
  naming convention, with the download verified against sdk-ng's own
  `sha256.sum` before repackaging. Host triples and archive formats
  (`.tar.bz2` for Linux/macOS, `.zip` for Windows - arduino-cli's
  downloader doesn't support the `.7z` format Zephyr ships Windows in)
  match what real Arduino package indexes use, confirmed against
  Arduino's own `package_index.json` and Espressif's
  `package_esp32_index.json`.

Run `tools/package/fetch_zephyr_toolchains.sh` before `make_release.sh` to
produce the three non-Linux archives into `dist/` along with
`dist/toolchains_manifest.tsv`; `make_release.sh` picks that manifest up
automatically (if present) and merges those hosts into
`package_nanotang_index.json`'s `tools[].systems`, alongside the Linux
entry it builds itself. Running `make_release.sh` alone (without first
running `fetch_zephyr_toolchains.sh`) still works and produces a
Linux-only index.

None of the toolchain archives need re-releasing when only the board
package version changes, only when the Zephyr SDK version itself changes
- `make_release.sh` regenerates their checksum/size entries every time
regardless, but you can skip re-uploading those specific assets to the
release if they're unchanged.

## Steps

1. Bump `platform.txt`'s `version=` line.
2. (Only needed when the Zephyr SDK version changed, or the very first
   time) fetch the non-Linux toolchain archives:
   ```sh
   tools/package/fetch_zephyr_toolchains.sh
   ```
   Downloads and repackages the macOS/Windows archives into `dist/` - see
   above. Needs network access to GitHub; no macOS/Windows machine needed.
3. Run the packaging script:
   ```sh
   tools/package/make_release.sh
   ```
   (or `tools/package/make_release.sh <version>` to override the version
   it reads from `platform.txt`). This writes the board + Linux toolchain
   archives to `dist/` (gitignored) and regenerates
   `package_nanotang_index.json` at the repo root with real SHA-256
   checksums and byte sizes - merging in whatever `fetch_zephyr_toolchains.sh`
   already placed in `dist/` from step 2, if any.
4. Sanity-check the index:
   ```sh
   python3 -m json.tool package_nanotang_index.json
   ```
5. Create a GitHub Release tagged `v<version>` on the repo and attach every
   archive under `dist/` (board package + however many toolchain archives
   are present).
6. Commit the regenerated `package_nanotang_index.json` and push.
7. Verify end-to-end before telling anyone the release is ready:
   ```sh
   arduino-cli core update-index --additional-urls \
     https://raw.githubusercontent.com/pschatzmann/arduino-nanotang/main/package_nanotang_index.json
   arduino-cli core install nanotang:tangnano20k --additional-urls \
     https://raw.githubusercontent.com/pschatzmann/arduino-nanotang/main/package_nanotang_index.json
   arduino-cli compile --fqbn nanotang:tangnano20k:tangnano20k examples/Blink
   ```
   A local dry run against a `file://` URL for the just-generated
   `package_nanotang_index.json` works too, and doesn't need step 4/5 done
   first - useful for testing the packaging itself before actually
   publishing a release.

`GITHUB_REPO` (default `pschatzmann/arduino-nanotang`), `ZEPHYR_SDK_DIR`
(default `~/zephyr-sdk-0.17.0`), and `TOOLCHAIN_VERSION` (default: read
from the SDK's own `sdk_version` file) are all overridable environment
variables for `make_release.sh` - see the script's own header comment.
