#!/usr/bin/env python3
"""Program a Tang Nano 20K via openFPGALoader.

Usage: upload.py [--tools-dir=<dir>] <boot_flash> <prog.fs> <prog_flash.bin> <data.bin>

boot_flash: "0" (Tools > Boot Mode: SRAM / SRAM + SDRAM) loads the
bitstream, which contains the whole program, into the FPGA's RAM - the
bitstream stored in flash is not touched, so a power cycle brings back
whatever that is. "1" (Flash / Flash + SDRAM) makes the board start the
sketch by itself at power-up: the core bitstream (the same for every
sketch, see tools/build_bitstream.py) is written to flash, replacing
whatever bitstream was stored there, and the sketch to the program
partition, from where the core's boot stub (boot.S) copies it into SRAM.
The bitstream write is skipped when the same bitstream was the last one
this script wrote (recorded in FLASHED_RECORD); set
NANOTANG_FORCE_BITSTREAM=1 to write it anyway, e.g. after the flash was
changed by other means or for a different board.

prog_flash.bin: the sketch's program, written to
TANGNANO20K_FLASH_PROGRAM_OFFSET (flash_layout.h) when boot_flash=1;
ignored (and need not exist) when boot_flash=0.

data.bin: FLASH_DATA payload (see tangnano20k_soc.h) plus, with Tools >
Boot Mode: ... + SDRAM, the code image startup.S copies to SDRAM; written
to TANGNANO20K_FLASH_DATA_OFFSET whenever non-empty, before the program -
independent of boot_flash, available in either boot mode.
"""
import hashlib
import os
import subprocess
import sys
from pathlib import Path

from find_tool import require_tool, take_tools_dir_arg

# Must match cores/tangnano20k/flash_layout.h.
FLASH_PROGRAM_OFFSET = 0x100000
FLASH_DATA_OFFSET = 0x110000

# SHA-256 of the core bitstream last written to flash by this script.
FLASHED_RECORD = Path.home() / ".cache" / "nanotang" / "flashed_bitstream.sha256"


def loader(*args):
    exe = require_tool("openFPGALoader", "FPGA programmer",
                       "Install oss-cad-suite (https://github.com/YosysHQ/oss-cad-suite-build) "
                       "to ~/oss-cad-suite or your distribution's openfpgaloader package")
    cmd = [exe, "-b", "tangnano20k", *args]
    print("+ " + " ".join(cmd))
    subprocess.run(cmd, check=True)


def main():
    take_tools_dir_arg(sys.argv)
    if len(sys.argv) != 5:
        sys.stderr.write(__doc__)
        return 1

    boot_flash = sys.argv[1] == "1"
    fs_path = Path(sys.argv[2])
    prog_flash_path = Path(sys.argv[3])
    data_path = Path(sys.argv[4])

    # Data first: with Tools > Boot Mode: ... + SDRAM it holds code that
    # startup.S copies to SDRAM on reset, so it must already be in flash
    # when a step below (re)starts the CPU with the new program.
    if data_path.exists() and data_path.stat().st_size > 0:
        loader("-f", "-o", str(FLASH_DATA_OFFSET), str(data_path))

    if not boot_flash:
        loader(str(fs_path))
        return 0

    if not prog_flash_path.exists() or prog_flash_path.stat().st_size == 0:
        sys.stderr.write(f"error: {prog_flash_path} missing or empty\n")
        return 1

    digest = hashlib.sha256(fs_path.read_bytes()).hexdigest()
    recorded = FLASHED_RECORD.read_text().strip() if FLASHED_RECORD.exists() else ""
    if digest != recorded or os.environ.get("NANOTANG_FORCE_BITSTREAM") == "1":
        loader("-f", str(fs_path))
        FLASHED_RECORD.parent.mkdir(parents=True, exist_ok=True)
        FLASHED_RECORD.write_text(digest + "\n")
    else:
        print("Core bitstream in flash is up to date - not rewritten")

    # Last: writing flash makes the FPGA reconfigure from it, which boots
    # the core bitstream, whose boot stub then copies this program.
    loader("-f", "-o", str(FLASH_PROGRAM_OFFSET), str(prog_flash_path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
