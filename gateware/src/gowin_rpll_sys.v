//Copyright (C)2014-2022 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: IP file
//GOWIN Version: V1.9.8.05
//Part Number: GW2A-LV18PG256C8/I7
//Device: GW2A-18C
//
// Vendored from sipeed/TangNano-20K-example (nestang/src/gowin_rpll_nes),
// renamed Gowin_rPLL_sys, for the arduino-tangnano20k core's system clock.
// This is plain Gowin IP-Core-Generator boilerplate (not proprietary/
// encrypted). clkout drives the whole SoC (replacing the old 20MHz
// external-clock-chip setup), clkoutp is the same frequency phase-shifted
// 180 degrees for the embedded SDRAM's clock pin (gateware/src/sdram.v).
// The actual output frequency is selected by the Tools > Clock Speed board
// menu (PLL_IDIV_SEL/PLL_FBDIV_SEL/PLL_ODIV_SEL below) - see boards.txt.

module Gowin_rPLL_sys (clkout, clkoutp, lock, reset, clkin);

output clkout;
output clkoutp;
output lock;
input reset;
input clkin;

wire clkoutd_o;
wire clkoutd3_o;
wire gw_gnd;

assign gw_gnd = 1'b0;

rPLL rpll_inst (
    .CLKOUT(clkout),
    .LOCK(lock),
    .CLKOUTP(clkoutp),
    .CLKOUTD(clkoutd_o),
    .CLKOUTD3(clkoutd3_o),
    .RESET(reset),
    .RESET_P(gw_gnd),
    .CLKIN(clkin),
    .CLKFB(gw_gnd),
    .FBDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .IDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .PSDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DUTYDA({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .FDLY({gw_gnd,gw_gnd,gw_gnd,gw_gnd})
);

// 27 -> 27 Mhz by default (IDIV_SEL/FBDIV_SEL/ODIV_SEL below matches the
// "proven config from nestang" this was vendored with). Overridden per the
// Tools > Clock Speed board menu (see boards.txt/build_bitstream.py) via
// -DPLL_IDIV_SEL/-DPLL_FBDIV_SEL/-DPLL_ODIV_SEL - each combination computed
// with apio/apycula's gowin_pll calculator against this exact part
// (GW2AR-18C), not hand-derived, since the VCO (IDIV/FBDIV ratio) and
// output (ODIV) must both land on values the PLL hardware actually
// supports. Must be kept in step with sys_parameters.v's CLK_FREQ, which
// top.v feeds to sdram_bus.v/ws2812_strip.v for their own FREQ-derived
// timing - see build_bitstream.py.
`ifndef PLL_IDIV_SEL
`define PLL_IDIV_SEL 0
`endif
`ifndef PLL_FBDIV_SEL
`define PLL_FBDIV_SEL 0
`endif
`ifndef PLL_ODIV_SEL
`define PLL_ODIV_SEL 32
`endif
defparam rpll_inst.FCLKIN = "27";
defparam rpll_inst.IDIV_SEL = `PLL_IDIV_SEL;
defparam rpll_inst.FBDIV_SEL = `PLL_FBDIV_SEL;
defparam rpll_inst.ODIV_SEL = `PLL_ODIV_SEL;

defparam rpll_inst.DYN_IDIV_SEL = "false";
defparam rpll_inst.DYN_FBDIV_SEL = "false";
defparam rpll_inst.DYN_ODIV_SEL = "false";
defparam rpll_inst.PSDA_SEL = "1000";
defparam rpll_inst.DYN_DA_EN = "false";
defparam rpll_inst.DUTYDA_SEL = "1000";
defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
defparam rpll_inst.CLKOUT_DLY_STEP = 0;
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
defparam rpll_inst.CLKFB_SEL = "internal";
defparam rpll_inst.CLKOUT_BYPASS = "false";
defparam rpll_inst.CLKOUTP_BYPASS = "false";
defparam rpll_inst.CLKOUTD_BYPASS = "false";
defparam rpll_inst.DYN_SDIV_SEL = 2;
defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
defparam rpll_inst.DEVICE = "GW2AR-18C";

endmodule //Gowin_rPLL_sys
