#!/usr/bin/env python3
"""Turn a linked NanoTangArduino .elf into a Gowin bitstream (.fs) by baking
a program into the gateware's SRAM initialization files and running the
open-source FPGA flow (yosys -> nextpnr-himbaechel -> gowin_pack).

Usage: build_bitstream.py <prog.elf> <objcopy> <build_dir> [ai_accel] [boot_flash] [spi2_i2c2] [hw_muldiv] [i2s_rx] [clk_freq_hz] [pll_idiv] [pll_fbdiv] [pll_odiv]

ai_accel: "1" to synthesize the AI accelerator (gateware/src/ai_accel_bus.v
and friends, integrated from NanoTangAI) into the bitstream, per the
Tools > AI Accelerator board menu; "0" (default) leaves it out entirely.
Unlike an unused software library, that gateware costs real LUTs/BRAM
whenever it's present, whether or not a sketch uses it - see top.v's
`ifdef WITH_AI_ACCEL and docs/PERIPHERALS.md "AI accelerator".

boot_flash: "1" for Tools > Boot Mode: Flash, "0" (default) for the
original SRAM boot mode. This changes what actually gets baked into the
SRAM init files, and what tools/upload.py needs to do:

- boot_flash=0 (default, unchanged from before this mode existed): the
  WHOLE compiled program (0x000 - the IRQ vector - through the sketch's
  own .text/.data) is baked into SRAM. Every upload re-runs the full FPGA
  flow (~1-3 minutes), because the program lives in block RAM initialized
  at synthesis time.
- boot_flash=1: only the *fixed* low-memory core code (irq_vec.S's
  .text.irq at 0x000, boot.S's .text.boot at 0x380 - see link_cmd.ld) gets
  baked into SRAM - identical across every sketch compile, since neither
  file depends on sketch content. The sketch's actual program (0x400
  onward) is instead extracted to `{build_dir}/prog_flash.bin`, meant for
  tools/upload.py to write directly to the onboard SPI flash at
  TANGNANO20K_FLASH_PROGRAM_OFFSET (see flash_layout.h) - boot.S copies it
  into SRAM at runtime.

  Because that core-only SRAM image is identical across sketch compiles
  (for a given ai_accel/spi2_i2c2/hw_muldiv combination), the resulting
  bitstream is cached at ~/.cache/nanotang/bitstreams/<hash>.fs, keyed on
  the core image's own bytes plus every gateware source file plus the
  .cst plus those three menu flags - so an actual "resynthesize this SoC"
  cost is only ever paid once per distinct core/menu combination, not on
  every compile. A cache hit skips straight to copying the cached .fs; a
  miss runs the full flow as usual and then populates the cache. Deleting
  ~/.cache/nanotang/bitstreams/ is always safe - it only ever holds
  reproducible build outputs.

Independent of boot_flash: if the ELF has a `.flash_data` section (see
FLASH_DATA in tangnano20k_soc.h), its raw bytes are extracted to
`{build_dir}/data.bin` for tools/upload.py to write to
TANGNANO20K_FLASH_DATA_OFFSET - available in either boot mode.

spi2_i2c2: "1" to synthesize a second SPI + I2C port (Tools > Extra
SPI/I2C), reusing spi_master.v/od_gpio2.v directly on GPIO0-5 instead of a
dedicated bus; "0" (default) leaves it out and those 6 pins stay available
as plain GPIO. Also a real GPIO-pin cost like AI Accelerator's LUT/BRAM
cost, so gated the same way.

hw_muldiv: "1" for Tools > Hardware Multiply/Divide: Enabled, enabling
picorv32's real M-extension (ENABLE_MUL/ENABLE_DIV/ENABLE_FAST_MUL in
top.v); "0" (default) leaves the CPU as plain RV32I. This MUST match
platform.txt's build.march for this same sketch - boards.txt drives both
from the one menu choice, never set independently, since a mismatch means
an illegal instruction on real hardware (a sketch compiled for
rv32im_zicsr_zifencei run on a bitstream without ENABLE_MUL, or vice
versa the CPU having unused hardware for a plain-RV32I sketch, which is
harmless).

i2s_rx: "1" to wire GPIO6 to the I2S peripheral's receive input (Tools >
I2S Input), enabling I2S.read()/full duplex against an external I2S
microphone sharing the onboard MAX98357A's BCLK/WS lines; "0" (default)
leaves GPIO6 as plain GPIO and I2S.read() always reads back zero
immediately. Same real GPIO-pin cost as spi2_i2c2, gated the same way -
see gateware/src/i2s.v and docs/PERIPHERALS.md "Audio (I2S)".

clk_freq_hz/pll_idiv/pll_fbdiv/pll_odiv: driven together by the Tools >
Clock Speed board menu (Normal 27MHz / Low Power 13.5MHz / Overclocked
54MHz, default Normal). clk_freq_hz becomes gowin_rpll_sys.v's actual PLL
output and sys_parameters.v's CLK_FREQ (which top.v feeds to
sdram_bus.v/ws2812b_tgt.v for their own FREQ-derived timing); pll_idiv/
pll_fbdiv/pll_odiv are the exact IDIV_SEL/FBDIV_SEL/ODIV_SEL divider values
that produce it from the board's 27MHz oscillator - computed per option
with apycula's gowin_pll calculator against this exact part (GW2AR-18C),
not derived at build time, since only certain divider combinations are
valid PLL configurations. All four MUST move together (a clk_freq_hz that
doesn't match what the given dividers actually produce would desync
software baud-rate/timing math in build.f_cpu from the gateware's real
clock) - boards.txt drives all four from the one menu choice, same pattern
as hw_muldiv's build.march/build.libgcc_path. Defaults (27000000/0/0/32)
match the original fixed, non-configurable clock this core shipped with.
"""
import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

SRAM_ADDR_WIDTH = 14  # Must match gateware/src/sys_parameters.v and link_cmd.ld
DEVICE = "GW2AR-LV18QN88C8/I7"
FAMILY = "GW2A-18C"

REPO_ROOT = Path(__file__).resolve().parent.parent
GATEWARE_SRC = REPO_ROOT / "gateware" / "src"
CST_FILE = REPO_ROOT / "gateware" / "picorv32_20k.cst"
CACHE_DIR = Path.home() / ".cache" / "nanotang" / "bitstreams"

GATEWARE_SOURCES = [
    "picorv32.v",
    "sram8bit.v",
    "sram.v",
    "simpleuart.v",
    "uart_wrap.v",
    "reset.v",
    "systick.v",
    "tang_leds.v",
    "i2s.v",
    "pwm6.v",
    "spi_master.v",
    "od_gpio2.v",
    "gpio_bank.v",
    "ws2812b.v",
    "ws2812b_tgt.v",
    "extirq.v",
    "dma_engine.v",
    "qspi_flash.v",
    "int8_mac_lane.v",
    "dot_product_lane_array.v",
    "byte_interleave_ram.v",
    "dot_product_engine.v",
    "ai_accel_bus.v",
    "sdram.v",
    "sdram_bus.v",
    "gowin_rpll_sys.v",
    "top.v",
]


def run(cmd, **kwargs):
    print("+ " + " ".join(str(c) for c in cmd))
    subprocess.run(cmd, check=True, **kwargs)


def core_bitstream_cache_key(boot_image_path, ai_accel, spi2_i2c2, hw_muldiv, i2s_rx,
                              clk_freq_hz, pll_idiv, pll_fbdiv, pll_odiv):
    """Hashes everything that can affect a Boot Mode: Flash core bitstream,
    independent of sketch content: the fixed core image (irq_vec.S/boot.S,
    the only trace of those build_bitstream.py otherwise never reads),
    every gateware source file, the pin constraints, and the menu flags
    that gate what gets synthesized."""
    h = hashlib.sha256()
    h.update(boot_image_path.read_bytes())
    for name in GATEWARE_SOURCES + ["sys_parameters.v"]:
        h.update((GATEWARE_SRC / name).read_bytes())
    h.update(CST_FILE.read_bytes())
    h.update(
        f"ai_accel={int(ai_accel)},spi2_i2c2={int(spi2_i2c2)},hw_muldiv={int(hw_muldiv)},"
        f"i2s_rx={int(i2s_rx)},clk_freq_hz={clk_freq_hz},pll_idiv={pll_idiv},"
        f"pll_fbdiv={pll_fbdiv},pll_odiv={pll_odiv}".encode()
    )
    return h.hexdigest()


def main():
    if len(sys.argv) not in (4, 5, 6, 7, 8, 9, 10, 11, 12, 13):
        sys.stderr.write(__doc__)
        return 1

    elf_path, objcopy, build_dir = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
    ai_accel = len(sys.argv) >= 5 and sys.argv[4] == "1"
    boot_flash = len(sys.argv) >= 6 and sys.argv[5] == "1"
    spi2_i2c2 = len(sys.argv) >= 7 and sys.argv[6] == "1"
    hw_muldiv = len(sys.argv) >= 8 and sys.argv[7] == "1"
    i2s_rx = len(sys.argv) >= 9 and sys.argv[8] == "1"
    # Clock Speed menu: all four move together (see the docstring above) -
    # default to the original fixed 27MHz/0/0/32 config if not given.
    clk_freq_hz = int(sys.argv[9]) if len(sys.argv) >= 10 else 27_000_000
    pll_idiv = int(sys.argv[10]) if len(sys.argv) >= 11 else 0
    pll_fbdiv = int(sys.argv[11]) if len(sys.argv) >= 12 else 0
    pll_odiv = int(sys.argv[12]) if len(sys.argv) >= 13 else 32
    build_dir.mkdir(parents=True, exist_ok=True)

    # FLASH_DATA payload, independent of boot_flash - empty (0 bytes) if the
    # sketch doesn't use any (objcopy's --only-section produces an empty,
    # valid file rather than erroring when the section doesn't exist).
    data_bin_path = build_dir / "data.bin"
    run([objcopy, "-O", "binary", "--only-section=.flash_data", str(elf_path), str(data_bin_path)])

    cached_fs = None
    if boot_flash:
        # Fixed, sketch-independent core image for SRAM: just the IRQ
        # vector and the boot stub (see link_cmd.ld/boot.S) - everything
        # else is zero-padded by gen_mem_init.py below.
        bin_path = build_dir / "boot_image.bin"
        run([
            objcopy, "-O", "binary",
            "--only-section=.text.irq", "--only-section=.text.boot",
            str(elf_path), str(bin_path),
        ])

        # The sketch's own program (0x400 onward), extracted separately for
        # tools/upload.py to write to flash instead of baking it into SRAM.
        # objcopy's binary output starts at the lowest remaining section's
        # address, so this file's first byte is SRAM address 0x400's byte -
        # exactly what boot.S's copy loop expects to receive.
        prog_flash_path = build_dir / "prog_flash.bin"
        run([
            objcopy, "-O", "binary",
            "-R", ".text.irq", "-R", ".irq_scratch", "-R", ".text.boot", "-R", ".flash_data",
            str(elf_path), str(prog_flash_path),
        ])

        cache_key = core_bitstream_cache_key(bin_path, ai_accel, spi2_i2c2, hw_muldiv, i2s_rx,
                                              clk_freq_hz, pll_idiv, pll_fbdiv, pll_odiv)
        cached_fs = CACHE_DIR / f"{cache_key}.fs"
        fs_path = build_dir / "prog.fs"
        if cached_fs.exists():
            shutil.copy(cached_fs, fs_path)
            print(f"Reused cached core bitstream ({cached_fs}) - skipped resynthesis")
            print(f"Bitstream written to {fs_path}")
            return 0
    else:
        bin_path = build_dir / "prog.bin"
        run([objcopy, "-O", "binary", "-R", ".flash_data", str(elf_path), str(bin_path)])

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

    # All gateware sources are always read - yosys prunes any module never
    # instantiated from `top` (confirmed via its "Removing unused module"
    # output), so ai_accel_bus.v and its dependencies cost nothing when
    # WITH_AI_ACCEL isn't defined and top.v's `ifdef excludes them.
    defines = []
    if ai_accel:
        defines.append("-DWITH_AI_ACCEL")
    if boot_flash:
        defines.append("-DBOOT_FROM_FLASH")
    if spi2_i2c2:
        defines.append("-DWITH_SPI2_I2C2")
    if hw_muldiv:
        defines.append("-DWITH_HW_MULDIV")
    if i2s_rx:
        defines.append("-DWITH_I2S_RX")
    # Clock Speed menu - always passed explicitly (rather than relying on
    # the Verilog `ifndef defaults) so the PLL dividers and CLK_FREQ can
    # never drift out of step with each other.
    defines.append(f"-DCLK_FREQ_HZ={clk_freq_hz}")
    defines.append(f"-DPLL_IDIV_SEL={pll_idiv}")
    defines.append(f"-DPLL_FBDIV_SEL={pll_fbdiv}")
    defines.append(f"-DPLL_ODIV_SEL={pll_odiv}")
    define = "read_verilog " + " ".join(defines) if defines else "read_verilog"
    json_path = build_dir / "top.json"
    run([
        "yosys",
        "-p",
        f"{define} {' '.join(GATEWARE_SOURCES)}; synth_gowin -top top -json {json_path}",
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

    if cached_fs is not None:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        shutil.copy(fs_path, cached_fs)
        print(f"Cached core bitstream at {cached_fs} for future fast uploads")

    print(f"Bitstream written to {fs_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
