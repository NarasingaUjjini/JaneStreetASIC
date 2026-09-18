// Copyright (c) 2026 Narasinga Ujjini
// SPDX-License-Identifier: Apache-2.0
`default_nettype none

module cycle_uart_rx #(
    parameter BAUD_DIV = 8
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg        valid,
    output reg  [7:0] data,
    input  wire       ready
);
  localparam DIV_W = (BAUD_DIV <= 1) ? 1 : $clog2(BAUD_DIV * 2 + 1);

  localparam [1:0] ST_IDLE = 2'd0;
  localparam [1:0] ST_START = 2'd1;
  localparam [1:0] ST_DATA = 2'd2;
  localparam [1:0] ST_STOP = 2'd3;

  reg [1:0] state;
  reg [DIV_W-1:0] baud_cnt;
  reg [2:0] bit_idx;
  reg [7:0] shifter;
  reg rx_q, rx_qq;

  wire rx_f = rx_qq;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_q  <= 1'b1;
      rx_qq <= 1'b1;
    end else begin
      rx_q  <= rx;
      rx_qq <= rx_q;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state    <= ST_IDLE;
      baud_cnt <= {DIV_W{1'b0}};
      bit_idx  <= 3'd0;
      shifter  <= 8'd0;
      valid    <= 1'b0;
      data     <= 8'd0;
    end else begin
      if (valid && ready) valid <= 1'b0;

      case (state)
        ST_IDLE: begin
          if (rx_f == 1'b0) begin
            state    <= ST_START;
            baud_cnt <= {DIV_W{1'b0}};
          end
        end
        ST_START: begin
          if (baud_cnt == BAUD_DIV[DIV_W-1:0] / 2) begin
            baud_cnt <= {DIV_W{1'b0}};
            if (rx_f == 1'b0) begin
              state   <= ST_DATA;
              bit_idx <= 3'd0;
            end else state <= ST_IDLE;
          end else baud_cnt <= baud_cnt + 1'b1;
        end
        ST_DATA: begin
          if (baud_cnt == BAUD_DIV[DIV_W-1:0] - 1'b1) begin
            baud_cnt <= {DIV_W{1'b0}};
            shifter  <= {rx_f, shifter[7:1]};
            if (bit_idx == 3'd7) state <= ST_STOP;
            else bit_idx <= bit_idx + 1'b1;
          end else baud_cnt <= baud_cnt + 1'b1;
        end
        ST_STOP: begin
          if (baud_cnt == BAUD_DIV[DIV_W-1:0] - 1'b1) begin
            baud_cnt <= {DIV_W{1'b0}};
            state    <= ST_IDLE;
            if (rx_f == 1'b1) begin
              data  <= shifter;
              valid <= 1'b1;
            end
          end else baud_cnt <= baud_cnt + 1'b1;
        end
        default: state <= ST_IDLE;
      endcase
    end
  end
endmodule
