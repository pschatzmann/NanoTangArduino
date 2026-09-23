#!/usr/bin/env bash
# Behavioural checks that don't need the FPGA flow or a board:
#   - iverilog test benches for the Arduino-core gateware (tb_*.v here):
#     systick counters, UART FIFOs, GPIO/LED set/clear registers, SPI
#     modes against a spec-following slave model, WS2812 strip streaming,
#     the SDRAM bus adapter (against sdram_stub.v), and the CAN controller (three nodes on one bus, checked against
#     reference bitstreams from gen_can_ref.py, an independent encoder).
#   - host-compiled tests of the core's printf family and mem*() functions
#     against glibc (host/*.c). The core sources are compiled for the host
#     and their symbols prefixed with t_ (objcopy), so they can't collide
#     with glibc's own.
# Called by tools/run_tests.sh; also runnable on its own. Exits non-zero
# on any failure.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SIM="$ROOT/tools/sim"
GW="$ROOT/gateware/src"
CORE="$ROOT/cores/tangnano20k"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
FAIL=0

run_tb() {
  local tb="$1"; shift
  local srcs=()
  for f in "$@"; do srcs+=("$GW/$f"); done
  # Verilog-2005, as yosys reads it (gpio_bank.v names a block `bit`,
  # a SystemVerilog keyword).
  if ! iverilog -g2005 -I"$OUT" -o "$OUT/$tb" "$SIM/$tb.v" "${srcs[@]}" >"$OUT/$tb.log" 2>&1; then
    echo "  FAIL: $tb did not compile - $(head -1 "$OUT/$tb.log")"; FAIL=1; return
  fi
  local result
  result="$(vvp -n "$OUT/$tb" 2>&1 | grep -E 'PASS|FAIL|MISMATCH|want|got' | tail -5)"
  if echo "$result" | tail -1 | grep -q PASS; then
    echo "  PASS: $tb - $(echo "$result" | tail -1)"
  else
    echo "  FAIL: $tb"; echo "$result" | sed 's/^/        /'; FAIL=1
  fi
}

if command -v iverilog >/dev/null 2>&1; then
  run_tb tb_systick systick.v
  run_tb tb_uart uart_wrap.v simpleuart.v
  run_tb tb_gpio gpio_bank.v tang_leds.v
  run_tb tb_spi spi_master.v
  run_tb tb_ws ws2812_strip.v
  run_tb tb_sdram_bus sdram_bus.v ../../tools/sim/sdram_stub.v
  if python3 "$SIM/gen_can_ref.py" "$OUT/can_ref.vh"; then
    run_tb tb_can can_ctrl.v
  else
    echo "  FAIL: gen_can_ref.py"; FAIL=1
  fi
else
  echo "  WARN: iverilog not found - skipping gateware test benches"
fi

run_host() {
  local name="$1" src="$2"
  # -fno-stack-protector: the host compiler's stack-check call would get
  # the t_ prefix too and fail to link.
  if { gcc -O2 -w -fno-builtin -fno-stack-protector -c "$CORE/$src" -o "$OUT/$name.core.o" &&
       objcopy --prefix-symbols=t_ "$OUT/$name.core.o" "$OUT/$name.t.o" &&
       gcc -O2 -w "$SIM/host/$name.c" "$OUT/$name.t.o" -lm -o "$OUT/$name"; } >"$OUT/$name.log" 2>&1; then
    local result
    if result="$("$OUT/$name")"; then
      echo "  PASS: $name - $(echo "$result" | tail -1)"
    else
      echo "  FAIL: $name"; echo "$result" | sed 's/^/        /'; FAIL=1
    fi
  else
    echo "  FAIL: $name did not build:"; sed 's/^/        /' "$OUT/$name.log" | head -10; FAIL=1
  fi
}

if command -v gcc >/dev/null 2>&1 && command -v objcopy >/dev/null 2>&1; then
  run_host printf_test tangnano20k_printf.c
  run_host mem_test tangnano20k_libc.c
else
  echo "  WARN: gcc/objcopy not found - skipping host tests"
fi

exit $FAIL
