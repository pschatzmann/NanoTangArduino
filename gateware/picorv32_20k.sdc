// Timing constraints: 20MHz external clock (period 50ns).
create_clock -name clk -period 50 -waveform {0 25} [get_ports {clk}]
