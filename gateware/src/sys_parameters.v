/* Checked-in defaults: 64KB internal SRAM, 27MHz system clock (27MHz
 * oscillator through Gowin_rPLL_sys - see top.v). CLK_FREQ is overridden
 * per the Tools > Clock Speed board menu via -DCLK_FREQ_HZ, and MUST stay
 * in step with gowin_rpll_sys.v's PLL_IDIV_SEL/PLL_FBDIV_SEL/PLL_ODIV_SEL
 * for the same menu choice - see build_bitstream.py. */
localparam SRAM_ADDR_WIDTH = 14;
`ifndef CLK_FREQ_HZ
`define CLK_FREQ_HZ 27000000
`endif
localparam CLK_FREQ = `CLK_FREQ_HZ;
