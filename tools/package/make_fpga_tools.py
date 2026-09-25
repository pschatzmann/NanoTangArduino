#!/usr/bin/env python3
"""Builds the oss-cad-suite-gowin Boards Manager tool: the parts of a
YosysHQ oss-cad-suite build (https://github.com/YosysHQ/oss-cad-suite-build)
that tools/build_bitstream.py and tools/upload.py need - yosys,
nextpnr-himbaechel with the GW2A-18C chip database, apicula's gowin_pack
(with the suite's own Python) and openFPGALoader - for every host Boards
Manager installs the core on. The full suite is 2-3GB unpacked per host,
most of it for other tools and FPGA families.

The version is the one platform.txt's fpga_tools.path pins
({runtime.tools.oss-cad-suite-gowin-<version>.path}); version 2026.9.25
is the suite released as 2026-09-25. To move to a newer suite, change that
line, run this script, and check that a full build still works (yosys and
nextpnr changes do break the flow now and then - see the $buf note in
build_bitstream.py).

For each host it downloads the suite (cached in
~/.cache/nanotang-release/oss-cad-suite/), keeps the files listed below
plus every shared library they load (found by reading the binaries' ELF,
PE or Mach-O dependency lists, so the result works on hosts this script
can't run on), and writes
  dist/oss-cad-suite-gowin-<version>-<host>.tar.bz2
  dist/fpga_tools_manifest.tsv  (host, archive, sha256, size - read by
                                 make_release.sh)
arm64 macOS gets the x86_64 archive (there is no arm64 suite build; it runs
under Rosetta 2).

Requires gh (authenticated) and objdump (binutils, with PE support).

Usage: tools/package/make_fpga_tools.py [--keep-staging]
"""
import argparse
import hashlib
import re
import shutil
import struct
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
DIST = ROOT / "dist"
CACHE = Path.home() / ".cache" / "nanotang-release" / "oss-cad-suite"
TOOL_NAME = "oss-cad-suite-gowin"

# Boards Manager host -> oss-cad-suite asset name.
HOSTS = {
    "x86_64-pc-linux-gnu": "linux-x64",
    "x86_64-apple-darwin": "darwin-x64",
    "x86_64-mingw32": "windows-x64",
}
ALIASES = {"arm64-apple-darwin": "x86_64-apple-darwin"}

# The programs, by base name: their bin/ wrappers and libexec/ binaries
# (Linux/macOS) or bin/ executables (Windows) are kept.
PROGRAMS = ["yosys", "yosys-abc", "nextpnr-himbaechel", "gowin_pack",
            "openFPGALoader", "tabbypy3", "python3", "python3.11"]
# Other files and folders kept as they are (relative to the suite root).
KEEP = [
    "VERSION", "README", "license", "etc/cacert.pem", "py3bin",
    "lib/ld-linux-x86-64.so.2",           # Linux: the bin/ wrappers run it
    "lib/yosys-abc",                      # yosys runs ABC from here (a link to bin/)
    "lib/python3.exe", "lib/python3.11.exe",  # Windows: runs gowin_pack
    "share/yosys",
    "share/openFPGALoader",
    "share/nextpnr/himbaechel/gowin/chipdb-GW2A-18C.bin",
]
# Python: the standard library minus these, plus only the site-packages
# gowin_pack imports (apycula falls back to msgpack/cattrs when msgspec,
# numpy and fastcrc are missing - they aren't in the suite).
PY_STDLIB_SKIP = {"test", "idlelib", "tkinter", "turtledemo", "lib2to3",
                  "ensurepip", "unittest", "distutils", "pydoc_data",
                  "site-packages", "config-3.11-x86_64-linux-gnu",
                  "config-3.11-darwin"}
PY_SITE_KEEP = ["apycula", "msgpack", "cattrs", "cattr", "attr", "attrs",
                "typing_extensions.py", "_distutils_hack",
                "distutils-precedence.pth"]


def read_tool_version():
    text = (ROOT / "platform.txt").read_text()
    m = re.search(r"^fpga_tools\.path=\{runtime\.tools\." + TOOL_NAME + r"-(.+)\.path\}$",
                  text, re.MULTILINE)
    if not m:
        sys.exit("ERROR: no fpga_tools.path line in platform.txt")
    return m.group(1)


def suite_date(version):
    y, mo, d = (int(x) for x in version.split("."))
    return f"{y:04d}{mo:02d}{d:02d}", f"{y:04d}-{mo:02d}-{d:02d}"


def download(asset, tag):
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / asset
    if not path.exists():
        print(f"== Downloading {asset} ==", flush=True)
        subprocess.run(["gh", "release", "download", tag, "-R", "YosysHQ/oss-cad-suite-build",
                        "-p", asset, "-D", str(CACHE)], check=True)
    return path


# --- Shared library dependencies ------------------------------------------

def elf_or_pe_needed(path):
    """Library names an ELF or PE file loads, via objdump -p."""
    r = subprocess.run(["objdump", "-p", str(path)], capture_output=True, text=True)
    names = re.findall(r"^\s+NEEDED\s+(\S+)", r.stdout, re.MULTILINE)
    names += re.findall(r"^\s+DLL Name: (\S+)", r.stdout, re.MULTILINE)
    return names


LC_DYLIB_CMDS = {0xC, 0x80000018, 0x8000001F, 0x20, 0x80000023}


def macho_needed(path):
    """Library install names a Mach-O file (thin or fat) loads."""
    data = path.read_bytes()
    offsets = []
    if data[:4] == b"\xca\xfe\xba\xbe":  # fat, big-endian header
        (n,) = struct.unpack(">I", data[4:8])
        for i in range(n):
            _cputype, _sub, off, _size, _align = struct.unpack(">5I", data[8 + 20 * i:28 + 20 * i])
            offsets.append(off)
    else:
        offsets.append(0)
    names = []
    for base in offsets:
        magic = struct.unpack("<I", data[base:base + 4])[0]
        if magic not in (0xFEEDFACF, 0xFEEDFACE):
            continue
        ncmds = struct.unpack("<I", data[base + 16:base + 20])[0]
        pos = base + (32 if magic == 0xFEEDFACF else 28)
        for _ in range(ncmds):
            cmd, size = struct.unpack("<II", data[pos:pos + 8])
            if cmd in LC_DYLIB_CMDS:
                (name_off,) = struct.unpack("<I", data[pos + 8:pos + 12])
                raw = data[pos + name_off:pos + size]
                names.append(raw.split(b"\0", 1)[0].decode())
            pos += size
    return names


def binary_kind(path):
    try:
        with open(path, "rb") as f:
            head = f.read(4)
    except OSError:
        return None
    if head == b"\x7fELF":
        return "elf"
    if head[:2] == b"MZ":
        return "pe"
    if head in (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe"):
        return "macho"
    return None


def library_index(suite):
    """Base name -> paths of every file in the suite (for resolving the
    names in dependency lists; macOS install names like
    @rpath/QtCore.framework/Versions/A/QtCore resolve by their tail)."""
    index = {}
    for p in suite.rglob("*"):
        if p.is_file() or p.is_symlink():
            index.setdefault(p.name.lower(), []).append(p)
    for paths in index.values():
        paths.sort(key=lambda p: len(p.parts))  # lib/x before lib/sub/x
    return index


def resolve(name, index, suite):
    base = name.rsplit("/", 1)[-1].lower()
    candidates = index.get(base, [])
    if "/" in name:
        # Prefer the candidate whose path ends like the install name.
        tail = name.split("/")
        tail = [t for t in tail if not t.startswith("@")]
        for c in candidates:
            if c.relative_to(suite).parts[-len(tail):] == tuple(tail):
                return c
    return candidates[0] if candidates else None


def dependency_closure(suite, roots):
    index = library_index(suite)
    todo = [p for p in roots if binary_kind(p)]
    seen = set(todo)
    while todo:
        p = todo.pop()
        kind = binary_kind(p)
        names = macho_needed(p) if kind == "macho" else elf_or_pe_needed(p)
        for name in names:
            dep = resolve(name, index, suite)
            if dep is None:
                continue  # a system library
            for q in (dep, dep.resolve()):
                if q not in seen and q.exists():
                    seen.add(q)
                    todo.append(q)
    return seen


# --- Selecting the files ---------------------------------------------------

def framework_dir(path, suite):
    """The .framework folder a macOS framework binary is in, if any."""
    for parent in path.relative_to(suite).parents:
        if parent.name.endswith(".framework"):
            return suite / parent
    return None


def select(suite):
    keep = set()

    def add(p):
        if p.is_dir() and not p.is_symlink():
            keep.update(q for q in p.rglob("*") if not q.is_dir() or q.is_symlink())
        elif p.exists() or p.is_symlink():
            keep.add(p)

    for d in ("bin", "libexec"):
        for p in (suite / d).glob("*"):
            stem = p.name.split(".exe")[0].split(".bat")[0]
            if stem in PROGRAMS or p.name in PROGRAMS:
                add(p)
    for rel in KEEP:
        add(suite / rel)

    for py in (suite / "lib").glob("python3.*"):
        if not py.is_dir():
            continue
        for p in py.iterdir():
            if p.name not in PY_STDLIB_SKIP:
                add(p)
        for name in PY_SITE_KEEP:
            add(py / "site-packages" / name)

    closure = dependency_closure(suite, [p for p in keep if p.is_file()])
    for p in closure:
        fw = framework_dir(p, suite)
        if fw is not None:
            add(fw)
        else:
            add(p)
    # Keep the symlinks that point at a kept library (libfoo.so.1 ->
    # libfoo.so.1.2.3): the loader looks for the link's name.
    for p in (suite / "lib").glob("*"):
        if p.is_symlink() and p.resolve() in closure:
            keep.add(p)
    return keep


def build_host(host, asset_name, tag, version, keep_staging):
    archive = download(asset_name, tag)
    stage = CACHE / "stage" / host
    shutil.rmtree(stage, ignore_errors=True)
    stage.mkdir(parents=True)
    print(f"== Unpacking {archive.name} ==", flush=True)
    with tarfile.open(archive) as tf:
        tf.extractall(stage, filter="tar")
    suite = stage / "oss-cad-suite"

    print(f"== Selecting files for {host} ==", flush=True)
    keep = select(suite)
    out_name = f"{TOOL_NAME}-{version}-{host}.tar.bz2"
    out = DIST / out_name
    root = f"{TOOL_NAME}"
    # Directories first, then files, then symlinks: arduino-cli's extractor
    # doesn't create a symlink's parent folder, nor a link to a file it
    # hasn't extracted yet.
    dirs = {q for p in keep for q in p.relative_to(suite).parents if q != Path(".")}
    with tarfile.open(out, "w:bz2") as tf:
        tf.add(suite, arcname=root, recursive=False)
        for d in sorted(dirs):
            tf.add(suite / d, arcname=f"{root}/{d}", recursive=False)
        for p in sorted(keep, key=lambda p: (p.is_symlink(), p)):
            tf.add(p, arcname=f"{root}/{p.relative_to(suite)}", recursive=False)
    if not keep_staging:
        shutil.rmtree(stage)
    size = out.stat().st_size
    sha = hashlib.sha256(out.read_bytes()).hexdigest()
    print(f"   {out_name}: {len(keep)} files, {size / 1e6:.0f}MB", flush=True)
    return out_name, sha, size


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--keep-staging", action="store_true",
                        help="keep the unpacked, trimmed suites (in the cache folder)")
    parser.add_argument("--host", action="append", choices=list(HOSTS),
                        help="build only this host (repeatable; default: all)")
    args = parser.parse_args()
    for tool in ("gh", "objdump"):
        if shutil.which(tool) is None:
            sys.exit(f"ERROR: '{tool}' not found on PATH")

    version = read_tool_version()
    date, tag = suite_date(version)
    DIST.mkdir(exist_ok=True)
    rows = []
    for host in args.host or HOSTS:
        name, sha, size = build_host(host, f"oss-cad-suite-{HOSTS[host]}-{date}.tgz",
                                     tag, version, args.keep_staging)
        rows.append((host, name, sha, size))
    manifest = DIST / "fpga_tools_manifest.tsv"
    if args.host and manifest.exists():
        # Only some hosts rebuilt: keep the other hosts' rows.
        built = {r[0] for r in rows}
        for line in manifest.read_text().splitlines():
            row = line.split("\t")
            if row[0] not in built and row[0] not in ALIASES:
                rows.append(tuple(row))
    rows = [r for r in rows if r[0] not in ALIASES]
    for alias, host in ALIASES.items():
        rows += [(alias, n, s, z) for h, n, s, z in rows if h == host]
    manifest.write_text("".join(f"{h}\t{n}\t{s}\t{z}\n" for h, n, s, z in rows))
    print(f"== Wrote {manifest} ==")


if __name__ == "__main__":
    sys.exit(main())
