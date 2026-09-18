// Copyright (c) 2026 Narasinga Ujjini
// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// Dual-read, single-write flop RAM. 128 x 16 fits UART/SPI/I2C/JTAG
// firmware without an SRAM macro (~2k flip-flops).
// When USE_IHP_SRAM is defined, cycle_sram_ihp.v replaces this.

module cycle_mem #(
    parameter DEPTH  = 128,
    parameter DATA_W = 16,
    parameter ADDR_W = 7
) (
    input  wire               clk,
    input  wire               we,
    input  wire [ADDR_W-1:0]  waddr,
    input  wire [DATA_W-1:0]  wdata,
    input  wire [ADDR_W-1:0]  addr0,
    output wire [DATA_W-1:0]  rdata0,
    input  wire [ADDR_W-1:0]  addr1,
    output wire [DATA_W-1:0]  rdata1
);
  reg [DATA_W-1:0] mem[0:DEPTH-1];
  integer i;
  initial begin
    for (i = 0; i < DEPTH; i = i + 1) mem[i] = 16'hF000;  // HALT
  end
  always @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
  end
  assign rdata0 = mem[addr0];
  assign rdata1 = mem[addr1];
endmodule
