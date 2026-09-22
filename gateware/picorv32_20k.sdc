// Timing constraint on the physical clock input: the board's fixed 27MHz
// oscillator (period 37.037ns). The system clock (~26.845MHz) is derived
// from this via Gowin_rPLL_sys in top.v.
create_clock -name clk_27m -period 37.037 -waveform {0 18.5} [get_ports {clk_27m}]
