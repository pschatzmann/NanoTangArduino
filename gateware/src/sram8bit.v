/* Copyright (C) 2024 Grug Huhler YouTube Channel
 *
 * License: SPDX: BSD-2-Clause
 * 
 * This module implements an 8-bit wide SRAM that
 * can be initialized.
 * 
 * SRAM_ADDR_WIDTH sets depth to 2**SRAM_ADDR_WIDTH
 * Format of MEM_INIT_FILE is two hex digits per line in a text file.
 * 
 * Reset neither clears nor reinitializes memory.
 *
 * arduino-tangnano20k patch: the read-data register's async reset (`or negedge
 * reset_n` below) was removed - a harmless simplification (a plain
 * synchronous read register with no reset, whose value nothing ever reads
 * before the first genuine `ce & !wre` cycle). The `(* ram_style = "block" *)`
 * attribute on `mem` below forces yosys's Gowin memory_libmap pass to map
 * this array onto real block RAM instead of distributed LUT RAM - without
 * it, this array is small enough that yosys prefers LUTRAM by default,
 * which doesn't scale to this array's actual size (see
 * docs/KNOWN_LIMITATIONS.md).
 */

module sram8
  #(
    parameter SRAM_ADDR_WIDTH = 11,
    parameter MEM_INIT_FILE = ""
    )
   (
    input                         clk,
    input                         reset_n,
    input                         ce, 
    input                         wre,
    input [SRAM_ADDR_WIDTH - 1:0] addr,
    input [7:0]                   data_in,
    output [7:0]                  data_out
    );
   
   (* ram_style = "block" *)
   reg [7:0]     mem[(1 << SRAM_ADDR_WIDTH) - 1:0];
   reg [7:0]     data_out_reg;

   initial begin
      if (MEM_INIT_FILE != "") begin
         $readmemh(MEM_INIT_FILE, mem);
      end
   end

   assign data_out = data_out_reg;

   always @(posedge clk)
     if (ce & !wre)
       data_out_reg <= mem[addr];

   always @(posedge clk)
     if (ce & wre)
       mem[addr] <= data_in;
   
endmodule // sram8
