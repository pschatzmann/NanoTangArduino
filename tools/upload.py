#!/usr/bin/env python3
"""Program a Tang Nano 20K via openFPGALoader.

Usage: upload.py <boot_flash> <prog.fs> <prog_flash.bin> <data.bin>

boot_flash: "0" (Tools > Boot Mode: SRAM, default) programs the whole
bitstream, exactly as before this mode existed. "1" (Flash) instead
assumes a matching flash-boot bitstream has already been programmed once
(see docs/BUILDING.md's one-time setup step) and only flash-writes the
sketch itself - a fast operation, not a full FPGA rebuild+reprogram.

prog_flash.bin: the sketch's program, written to
TANGNANO20K_FLASH_PROGRAM_OFFSET (flash_layout.h) when boot_flash=1;
ignored (and need not exist) when boot_flash=0.

data.bin: FLASH_DATA payload (see tangnano20k_soc.h), written to
TANGNANO20K_FLASH_DATA_OFFSET whenever non-empty - independent of
boot_flash, available in either boot mode.
"""
import subprocess
import sys
from pathlib import Path

# Must match cores/tangnano20k/flash_layout.h.
FLASH_PROGRAM_OFFSET = 0x100000
FLASH_DATA_OFFSET = 0x110000


def main():
    if len(sys.argv) != 5:
        sys.stderr.write(__doc__)
        return 1

    boot_flash = sys.argv[1] == "1"
    fs_path = sys.argv[2]
    prog_flash_path = Path(sys.argv[3])
    data_path = Path(sys.argv[4])

    if boot_flash:
        if not prog_flash_path.exists() or prog_flash_path.stat().st_size == 0:
            sys.stderr.write(f"error: {prog_flash_path} missing or empty\n")
            return 1
        cmd = [
            "openFPGALoader", "-b", "tangnano20k",
            "-f", "-o", str(FLASH_PROGRAM_OFFSET),
            str(prog_flash_path),
        ]
        print("+ " + " ".join(cmd))
        subprocess.run(cmd, check=True)
    else:
        cmd = ["openFPGALoader", "-b", "tangnano20k", fs_path]
        print("+ " + " ".join(cmd))
        subprocess.run(cmd, check=True)

    if data_path.exists() and data_path.stat().st_size > 0:
        cmd = [
            "openFPGALoader", "-b", "tangnano20k",
            "-f", "-o", str(FLASH_DATA_OFFSET),
            str(data_path),
        ]
        print("+ " + " ".join(cmd))
        subprocess.run(cmd, check=True)

    return 0


if __name__ == "__main__":
    sys.exit(main())
