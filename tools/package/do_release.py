#!/usr/bin/env python3
"""Automates docs/RELEASING.md's release steps, including step 1: pass
--version to also bump platform.txt's version= line before packaging.
Without --version, it reads the version already in platform.txt and leaves
the file untouched.

Steps run, in order:
  1. (only with --version) bump platform.txt's version= line
  2. tools/package/fetch_zephyr_toolchains.sh   (macOS/Windows toolchains -
     skipped if dist/toolchains_manifest.tsv already exists; use
     --refresh-toolchains to force, or --skip-toolchains to never run it)
     and tools/package/make_fpga_tools.py        (FPGA tool archives, all
     hosts - skipped the same way, if dist/fpga_tools_manifest.tsv exists)
  3. tools/package/make_release.sh              (board + Linux toolchain
     archives, regenerates package_nanotang_index.json)
  4. python3 -m json.tool package_nanotang_index.json   (sanity check)
  5. git commit (and, with --push, push) the regenerated
     package_nanotang_index.json - *before* the release is created, so the
     release's tag points at a commit with matching version files
  6. gh release create/upload                   (creates the v<version>
     release if it doesn't exist yet, uploads every archive in dist/)
  7. arduino-cli core update-index / core install / compile libraries/Core/examples/Blink
     against the live raw index URL (skipped with --skip-verify)

Usage:
  tools/package/do_release.py [--push] [--skip-verify] [--skip-toolchains]
                               [--refresh-toolchains] [--draft] [--dry-run]
                               [--version VERSION] [--repo OWNER/REPO]

--dry-run runs steps 2-4 (build the archives, regenerate the index) but
skips the GitHub release, git commit/push, and verification - useful for
checking the packaging itself before actually publishing.

Requires `gh` to be authenticated (`gh auth status`) unless --dry-run is
given, and arduino-cli on PATH unless --skip-verify is given.
"""
import argparse
import functools
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

print = functools.partial(print, flush=True)

ROOT = Path(__file__).resolve().parent.parent.parent


def run(cmd, **kwargs):
    print(f"+ {' '.join(cmd)}")
    return subprocess.run(cmd, check=True, cwd=ROOT, **kwargs)


def read_version(root: Path) -> str:
    text = (root / "platform.txt").read_text()
    m = re.search(r"^version=(.+)$", text, re.MULTILINE)
    if not m:
        sys.exit("ERROR: no version= line found in platform.txt")
    return m.group(1).strip()


def bump_version(root: Path, version: str) -> None:
    path = root / "platform.txt"
    text = path.read_text()
    new_text, n = re.subn(r"^version=.+$", f"version={version}", text, count=1, flags=re.MULTILINE)
    if n != 1:
        sys.exit("ERROR: no version= line found in platform.txt")
    if new_text == text:
        print(f"== platform.txt already at version={version} ==")
        return
    path.write_text(new_text)
    print(f"== Bumped platform.txt to version={version} ==")


def require_tool(name: str):
    if shutil.which(name) is None:
        sys.exit(f"ERROR: '{name}' not found on PATH")


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                      formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--version",
                         help="release this version - also bumps platform.txt's version= "
                              "line (default: read the version already in platform.txt, "
                              "and don't touch the file)")
    parser.add_argument("--repo", default="pschatzmann/arduino-tangnano20k",
                         help="owner/repo for the GitHub release (default: %(default)s)")
    parser.add_argument("--skip-toolchains", action="store_true",
                         help="never run fetch_zephyr_toolchains.sh, even if dist/ is empty")
    parser.add_argument("--refresh-toolchains", action="store_true",
                         help="re-run fetch_zephyr_toolchains.sh even if dist/toolchains_manifest.tsv exists")
    parser.add_argument("--draft", action="store_true",
                         help="create the GitHub release as a draft")
    parser.add_argument("--push", action="store_true",
                         help="push the commit to origin (default: commit locally only)")
    parser.add_argument("--skip-verify", action="store_true",
                         help="skip step 7's end-to-end arduino-cli verification")
    parser.add_argument("--dry-run", action="store_true",
                         help="build/package only - no GitHub release, no git commit/push, no verify")
    args = parser.parse_args()

    version = args.version or read_version(ROOT)
    tag = f"v{version}"
    dist = ROOT / "dist"
    index_path = ROOT / "package_nanotang_index.json"
    platform_txt = ROOT / "platform.txt"

    print(f"== Releasing {args.repo} {tag} ==")

    # Step 1: bump platform.txt, only when a version was explicitly requested.
    if args.version:
        bump_version(ROOT, args.version)

    if not args.dry_run:
        require_tool("gh")
    if not args.skip_verify and not args.dry_run:
        require_tool("arduino-cli")

    # Step 2: non-Linux toolchains (skipped by default once already fetched).
    manifest = dist / "toolchains_manifest.tsv"
    if args.skip_toolchains:
        print("== Skipping fetch_zephyr_toolchains.sh (--skip-toolchains) ==")
    elif manifest.exists() and not args.refresh_toolchains:
        print(f"== Skipping fetch_zephyr_toolchains.sh ({manifest} already exists; "
              f"pass --refresh-toolchains to re-fetch) ==")
    else:
        run(["tools/package/fetch_zephyr_toolchains.sh"])

    # Step 2b: FPGA tool archives (skipped once built - they only change when
    # platform.txt's fpga_tools.path pins a new oss-cad-suite version).
    fpga_manifest = dist / "fpga_tools_manifest.tsv"
    if args.skip_toolchains:
        print("== Skipping make_fpga_tools.py (--skip-toolchains) ==")
    elif fpga_manifest.exists() and not args.refresh_toolchains:
        print(f"== Skipping make_fpga_tools.py ({fpga_manifest} already exists; "
              f"pass --refresh-toolchains to rebuild) ==")
    else:
        run([sys.executable, "tools/package/make_fpga_tools.py"])

    # Step 3: board + Linux toolchain archives, regenerate the index.
    run(["tools/package/make_release.sh", version])

    # Step 4: sanity-check the regenerated index.
    with index_path.open() as f:
        index = json.load(f)
    print(f"== {index_path.name} is valid JSON ==")

    # dist/ is never wiped (see make_release.sh), so it can still hold board
    # archives from earlier versions - only upload this version's one.
    board_archive = f"arduino-tangnano20k-{version}.tar.bz2"
    archives = sorted(
        p.name for p in dist.iterdir()
        if p.is_file() and p.suffix != ".tsv"
        and (not p.name.startswith("arduino-tangnano20k-") or p.name == board_archive)
    )
    if not archives:
        sys.exit(f"ERROR: no archives found in {dist}")
    print(f"== Archives to release: {', '.join(archives)} ==")

    if args.dry_run:
        print("== --dry-run: stopping before GitHub release / git commit / verify ==")
        return

    # Step 5: commit (and optionally push) platform.txt + the regenerated
    # index *before* the GitHub release is created, so the release's tag
    # points at a commit whose platform.txt/package_nanotang_index.json
    # already match the version being released - not the previous one.
    commit_paths = [str(index_path)]
    if args.version:
        commit_paths.append(str(platform_txt))
    status = subprocess.run(
        ["git", "status", "--porcelain", "--", *commit_paths],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.strip()
    if status:
        run(["git", "add", *commit_paths])
        run(["git", "commit", "-m",
             f"Release {tag}\n\n"
             f"Regenerated via tools/package/do_release.py."])
        if args.push:
            run(["git", "push"])
        else:
            print("== Committed locally; pass --push to push to origin ==")
    else:
        print(f"== Nothing to commit ({', '.join(commit_paths)} already match HEAD) ==")

    # Step 6: create the release if it doesn't exist yet, then upload assets.
    existing = subprocess.run(
        ["gh", "release", "view", tag, "--repo", args.repo],
        cwd=ROOT, capture_output=True, text=True,
    )
    if existing.returncode != 0:
        create_cmd = ["gh", "release", "create", tag, "--repo", args.repo,
                      "--title", tag, "--generate-notes"]
        if args.draft:
            create_cmd.append("--draft")
        run(create_cmd)
    else:
        print(f"== Release {tag} already exists, uploading/updating assets ==")

    run(["gh", "release", "upload", tag, *[str(dist / a) for a in archives],
         "--repo", args.repo, "--clobber"])

    # Step 7: end-to-end verification against the live raw index URL.
    if args.skip_verify:
        print("== Skipping step 7 verification (--skip-verify) ==")
        return

    raw_url = f"https://raw.githubusercontent.com/{args.repo}/main/{index_path.name}"
    fqbn_package = next(iter(index["packages"]))["name"]
    fqbn_arch = index["packages"][0]["platforms"][0]["architecture"]
    fqbn = f"{fqbn_package}:{fqbn_arch}:{fqbn_arch}"

    print(f"== Verifying {fqbn} installs and compiles via {raw_url} ==")
    run(["arduino-cli", "core", "update-index", "--additional-urls", raw_url])
    run(["arduino-cli", "core", "install", f"{fqbn_package}:{fqbn_arch}",
         "--additional-urls", raw_url])
    run(["arduino-cli", "compile", "--fqbn", fqbn, "libraries/Core/examples/Blink"])

    print(f"\nRelease {tag} done and verified.")


if __name__ == "__main__":
    main()
