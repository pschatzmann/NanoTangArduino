#!/usr/bin/env python3
"""Turn a linked NanoTangArduino .elf into a Gowin bitstream (.fs) by baking
the program into the gateware's SRAM initialization files and running the
open-source FPGA flow (yosys -> nextpnr-himbaechel -> gowin_pack).

This replaces the "upload" step of a normal Arduino board: because the
program lives in block RAM that's initialized at synthesis time, every
sketch change requires a full FPGA rebuild (expect ~1-3 minutes), not just a
quick flash write. See README.md for details and prerequisites.

Usage: build_bitstream.py <prog.elf> <objcopy> <build_dir>
"""
import shutil
import subprocess
import sys
from pathlib import Path

SRAM_ADDR_WIDTH = 13  # Must match gateware/src/sys_parameters.v and link_cmd.ld
DEVICE = "GW2AR-LV18QN88C8/I7"
FAMILY = "GW2A-18C"

REPO_ROOT = Path(__file__).resolve().parent.parent
GATEWARE_SRC = REPO_ROOT / "gateware" / "src"
CST_FILE = REPO_ROOT / "gateware" / "picorv32_20k.cst"

GATEWARE_SOURCES = [
    "picorv32.v",
    "sram8bit.v",
    "sram.v",
    "simpleuart.v",
    "uart_wrap.v",
    "reset.v",
    "systick.v",
    "tang_leds.v",
    "i2s_tx.v",
    "top.v",
]


def run(cmd, **kwargs):
    print("+ " + " ".join(str(c) for c in cmd))
    subprocess.run(cmd, check=True, **kwargs)


def main():
    if len(sys.argv) != 4:
        sys.stderr.write(__doc__)
        return 1

    elf_path, objcopy, build_dir = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
    build_dir.mkdir(parents=True, exist_ok=True)

    bin_path = build_dir / "prog.bin"
    run([objcopy, "-O", "binary", str(elf_path), str(bin_path)])

    # Regenerate the SRAM init files in place, alongside the rest of the
    # gateware sources, so the yosys read_verilog below picks them up.
    run([
        sys.executable,
        str(REPO_ROOT / "tools" / "gen_mem_init.py"),
        str(bin_path),
        str(SRAM_ADDR_WIDTH),
        str(GATEWARE_SRC),
    ])

    build_gateware = build_dir / "gateware"
    build_gateware.mkdir(parents=True, exist_ok=True)
    for name in GATEWARE_SOURCES + [f"mem_init{i}.ini" for i in range(4)] + ["sys_parameters.v"]:
        shutil.copy(GATEWARE_SRC / name, build_gateware / name)

    json_path = build_dir / "top.json"
    run([
        "yosys",
        "-p",
        f"read_verilog {' '.join(GATEWARE_SOURCES)}; synth_gowin -top top -json {json_path}",
    ], cwd=build_gateware)

    pnr_json = build_dir / "pnrtop.json"
    run([
        "nextpnr-himbaechel",
        "--json", str(json_path),
        "--write", str(pnr_json),
        "--device", DEVICE,
        "--vopt", f"family={FAMILY}",
        "--vopt", f"cst={CST_FILE}",
    ])

    fs_path = build_dir / "prog.fs"
    run(["gowin_pack", "-d", FAMILY, "-o", str(fs_path), str(pnr_json)])

    print(f"Bitstream written to {fs_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
