// Copyright (c) 2026 Narasinga Ujjini
// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// 4-deep 8-bit valid/ready FIFO.

module cycle_fifo #(
    parameter W = 8,
    parameter D = 4
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         we,
    input  wire [W-1:0] wdata,
    input  wire         re,
    output wire [W-1:0] rdata,
    output wire         empty,
    output wire         full
);
  localparam AW = $clog2(D);
  reg [W-1:0] mem[0:D-1];
  reg [AW-1:0] wptr, rptr;
  reg [AW:0] count;

  assign empty = (count == 0);
  assign full  = (count == D[AW:0]);
  assign rdata = mem[rptr];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wptr  <= {AW{1'b0}};
      rptr  <= {AW{1'b0}};
      count <= {(AW + 1) {1'b0}};
    end else begin
      if (we && !full) begin
        mem[wptr] <= wdata;
        wptr <= wptr + 1'b1;
      end
      if (re && !empty) begin
        rptr <= rptr + 1'b1;
      end
      case ({we && !full, re && !empty})
        2'b10: count <= count + 1'b1;
        2'b01: count <= count - 1'b1;
        default: count <= count;
      endcase
    end
  end
endmodule
