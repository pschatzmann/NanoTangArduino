# Releasing

How to cut a release that Arduino Boards Manager users can install via
`package_nanotang_index.json`. See [Building, installing, and
verifying](BUILDING.md#installing-via-boards-manager) for what the
resulting install experience looks like.

## What gets published

The board package plus, per supported host, one RISC-V toolchain archive
and one FPGA tools archive, all attached to one GitHub Release:

- `arduino-tangnano20k-<version>.tar.bz2` - the board package itself
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
package version changes, only when the Zephyr SDK version itself changes.
When `$ZEPHYR_SDK_DIR` doesn't exist, `make_release.sh` keeps the index's
existing `riscv-zephyr-elf` entry as it is - its URLs keep pointing at the
release that first published the archives.

- `oss-cad-suite-gowin-<version>-<host-triple>.tar.bz2` - the FPGA tools
  (yosys, nextpnr-himbaechel, apicula's `gowin_pack`, openFPGALoader), a
  second **tool** dependency. Each is the part of a
  [YosysHQ oss-cad-suite](https://github.com/YosysHQ/oss-cad-suite-build)
  build this flow needs: the four programs, the suite's Python for
  `gowin_pack`, the GW2A-18C chip database, and every shared library they
  load - about 75-105MB instead of the full suite's 500-750MB download.
  `tools/package/make_fpga_tools.py` downloads the suite for Linux x86_64,
  macOS x86_64 and Windows x86_64, trims it and writes
  `dist/fpga_tools_manifest.tsv`, which `make_release.sh` merges into the
  index. There is no arm64 macOS suite; Apple Silicon gets the x86_64
  archive, which runs under Rosetta 2.

  The version is pinned by `platform.txt`'s `fpga_tools.path` line
  (`{runtime.tools.oss-cad-suite-gowin-2026.9.25.path}` is the suite
  released as 2026-09-25). New yosys/nextpnr versions do break the flow
  now and then, so to move to a newer suite: change that line, run
  `make_fpga_tools.py`, install the result (unpack the Linux archive to
  `<data dir>/packages/nanotang/tools/oss-cad-suite-gowin/<version>/`,
  without its top folder) and check that a full build of an example,
  and its upload, still work before releasing. Like the RISC-V toolchain,
  the archives only need building and uploading when that version changes;
  without `dist/fpga_tools_manifest.tsv`, `make_release.sh` keeps the
  index's existing entry.

  The trimming finds libraries by reading the binaries' dependency lists,
  so it can't see files a program opens by path at run time (yosys runs
  ABC as `lib/yosys-abc`, for example - `make_fpga_tools.py`'s `KEEP`
  lists those). Only the Linux archive can be tested on a Linux machine;
  check the macOS and Windows ones on those systems when the suite
  version changes.

## Automated: `tools/package/do_release.py`

`tools/package/do_release.py` runs every step below end to end, including
the version bump. Requires `gh` authenticated (`gh auth status`) and
`arduino-cli` on `PATH` (unless `--skip-verify`/`--dry-run`).

```sh
# Bump platform.txt to 0.2.0, build the archives, regenerate the index -
# but don't touch GitHub, git, or run the arduino-cli verification.
tools/package/do_release.py --version 0.2.0 --dry-run

# Full release: bump platform.txt, build, create/update the v0.2.0 GitHub
# Release and upload every dist/ archive to it, commit platform.txt +
# package_nanotang_index.json, push, then verify end-to-end via
# arduino-cli against the live raw index URL.
tools/package/do_release.py --version 0.2.0 --push

# Re-run packaging for whatever version is already in platform.txt
# (no version bump) - e.g. to re-upload archives after fixing something.
tools/package/do_release.py
```

Other flags: `--repo owner/repo` (default `pschatzmann/arduino-tangnano20k`),
`--skip-toolchains` / `--refresh-toolchains` (control step 2, see below),
`--draft` (create the GitHub Release as a draft), `--skip-verify` (skip
step 7). Without `--push`, the version bump and index update are committed
locally but not pushed. See `tools/package/do_release.py --help` for the
full list.

## Steps (what the script above automates)

1. Bump `platform.txt`'s `version=` line.
2. (Only needed when the Zephyr SDK version changed, or the very first
   time) fetch the non-Linux toolchain archives:
   ```sh
   tools/package/fetch_zephyr_toolchains.sh
   ```
   Downloads and repackages the macOS/Windows archives into `dist/` - see
   above. Needs network access to GitHub; no macOS/Windows machine needed.
   Likewise, only when `platform.txt`'s `fpga_tools.path` version changed
   (or the very first time), build the FPGA tools archives for all hosts:
   ```sh
   tools/package/make_fpga_tools.py
   ```
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
5. Commit the regenerated `package_nanotang_index.json` (and `platform.txt`,
   if the version was bumped) and push - *before* creating the release, so
   the release's tag points at a commit whose version files already match
   the version being released.
6. Create a GitHub Release tagged `v<version>` on the repo and attach every
   archive under `dist/` (board package + however many toolchain archives
   are present).
7. Verify end-to-end before telling anyone the release is ready:
   ```sh
   arduino-cli core update-index --additional-urls \
     https://raw.githubusercontent.com/pschatzmann/arduino-tangnano20k/main/package_nanotang_index.json
   arduino-cli core install nanotang:tangnano20k --additional-urls \
     https://raw.githubusercontent.com/pschatzmann/arduino-tangnano20k/main/package_nanotang_index.json
   arduino-cli compile --fqbn nanotang:tangnano20k:tangnano20k libraries/Core/examples/Blink
   ```
   A local dry run against a `file://` URL for the just-generated
   `package_nanotang_index.json` works too, and doesn't need step 4/5 done
   first - useful for testing the packaging itself before actually
   publishing a release.

`GITHUB_REPO` (default `pschatzmann/arduino-tangnano20k`), `ZEPHYR_SDK_DIR`
(default `~/zephyr-sdk-0.17.0`), and `TOOLCHAIN_VERSION` (default: read
from the SDK's own `sdk_version` file) are all overridable environment
variables for `make_release.sh` - see the script's own header comment.
