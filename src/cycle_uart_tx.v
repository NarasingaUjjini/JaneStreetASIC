// Copyright (c) 2026 Narasinga Ujjini
// SPDX-License-Identifier: Apache-2.0
`default_nettype none

module cycle_uart_tx #(
    parameter BAUD_DIV = 8
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       we,
    input  wire [7:0] wdata,
    output wire       busy,
    output wire       tx
);
  localparam DIV_W = (BAUD_DIV <= 1) ? 1 : $clog2(BAUD_DIV + 1);

  reg [8:0] shifter;  // {stop, data[7:0]}
  reg [3:0] bits_left;
  reg [DIV_W-1:0] baud_cnt;
  reg active;
  reg tx_r;

  assign busy = active;
  assign tx   = active ? tx_r : 1'b1;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      shifter   <= 10'h3FF;
      bits_left <= 4'd0;
      baud_cnt  <= {DIV_W{1'b0}};
      active    <= 1'b0;
      tx_r      <= 1'b1;
    end else if (active) begin
      if (baud_cnt == BAUD_DIV[DIV_W-1:0] - 1'b1) begin
        baud_cnt  <= {DIV_W{1'b0}};
        tx_r      <= shifter[0];
        shifter   <= {1'b1, shifter[8:1]};
        if (bits_left == 0) active <= 1'b0;
        else bits_left <= bits_left - 1'b1;
      end else begin
        baud_cnt <= baud_cnt + 1'b1;
      end
    end else if (we) begin
      shifter   <= {1'b1, wdata};  // stop + data; start bit is already on the wire
      bits_left <= 4'd9;           // 8 data bits + stop
      baud_cnt  <= {DIV_W{1'b0}};
      active    <= 1'b1;
      tx_r      <= 1'b0;
    end
  end
endmodule
