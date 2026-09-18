// Copyright (c) 2026 Narasinga Ujjini
// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// IHP compiled SRAM wrapper.
// By default this is a 512x16 flop stand-in so RTL sim works without the PDK.
// When hardening with the IHP macro, define USE_IHP_SRAM and point LibreLane
// at RM_IHPSG13_1P_512x16_c2_bm_bist (same family as Tiny Tapeout's
// 1024x8 SRAM example: https://github.com/urish/ttihp-sram-test).
//
// CMOS5L uses the same SRAM macros as SG13G2 (OpenROAD-flow-scripts note).

module cycle_sram_ihp (
    input  wire        clk,
    input  wire        we,
    input  wire [8:0]  addr,
    input  wire [15:0] wdata,
    output wire [15:0] rdata
);
`ifdef USE_IHP_SRAM
  // Active-low chip/write enables. Bit-write mask all enabled.
  RM_IHPSG13_1P_512x16_c2_bm_bist u_sram (
      .CLK (clk),
      .CEN (1'b0),
      .GWEN(~we),
      .WEN (16'h0000),
      .A   (addr),
      .D   (wdata),
      .Q   (rdata)
  );
`else
  // Fallback: flop array. Do NOT use this for the 6x4 tapeout of a 512-deep
  // memory — it will not fit. The production path is the IHP macro above.
  // A 128-deep cycle_mem is the flop path used by the default top.
  reg [15:0] mem[0:511];
  reg [15:0] q;
  integer i;
  initial for (i = 0; i < 512; i = i + 1) mem[i] = 16'd0;
  always @(posedge clk) begin
    if (we) mem[addr] <= wdata;
    q <= mem[addr];
  end
  assign rdata = q;
`endif
endmodule
