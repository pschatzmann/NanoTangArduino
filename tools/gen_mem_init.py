#!/usr/bin/env python3
"""Convert a compiled program binary into the four 8-bit-lane $readmemh
initialization files the gateware's SRAM expects (one per byte lane, little
endian), replacing the reference project's conv_to_init.c.

Usage: gen_mem_init.py <prog.bin> <sram_addr_width> <out_dir>
"""
import sys


def main():
    if len(sys.argv) != 4:
        sys.stderr.write(__doc__)
        return 1

    bin_path, addr_width_s, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
    addr_width = int(addr_width_s)
    depth = 1 << addr_width

    with open(bin_path, "rb") as f:
        data = f.read()

    max_bytes = depth * 4
    if len(data) > max_bytes:
        sys.stderr.write(
            f"error: program is {len(data)} bytes, SRAM only holds {max_bytes} "
            f"bytes (SRAM_ADDR_WIDTH={addr_width})\n"
        )
        return 1

    lanes = [[], [], [], []]
    for i in range(depth):
        for lane in range(4):
            offset = i * 4 + lane
            byte = data[offset] if offset < len(data) else 0
            lanes[lane].append(f"{byte:02x}")

    for lane in range(4):
        with open(f"{out_dir}/mem_init{lane}.ini", "w") as f:
            f.write("\n".join(lanes[lane]) + "\n")

    return 0


if __name__ == "__main__":
    sys.exit(main())
