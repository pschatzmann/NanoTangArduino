#!/usr/bin/env python3
"""Program a Tang Nano 20K with a bitstream via openFPGALoader.

Usage: upload.py <prog.fs>
"""
import subprocess
import sys


def main():
    if len(sys.argv) != 2:
        sys.stderr.write(__doc__)
        return 1

    fs_path = sys.argv[1]
    cmd = ["openFPGALoader", "-b", "tangnano20k", fs_path]
    print("+ " + " ".join(cmd))
    subprocess.run(cmd, check=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
