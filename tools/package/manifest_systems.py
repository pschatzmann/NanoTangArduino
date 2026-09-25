#!/usr/bin/env python3
"""Prints the package index tools[].systems JSON for the archives listed in
one or more manifest files (host<TAB>archiveFileName<TAB>sha256<TAB>size per
line), as written by tools/package/make_fpga_tools.py and
fetch_zephyr_toolchains.sh. Missing manifest files are skipped.

Usage: manifest_systems.py <release_url> <manifest.tsv>...
"""
import csv
import json
import os
import sys

release_url = sys.argv[1]
systems = []
for manifest_path in sys.argv[2:]:
    if not os.path.exists(manifest_path):
        continue
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
