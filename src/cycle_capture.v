// Copyright (c) 2026 Narasinga Ujjini
// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// 64-sample x 8-bit capture / replay buffer.
// Capture samples `pins_in` every (period+1) clocks.
// Replay drives the recorded samples onto `pins_play` / `oe_play`.

module cycle_capture #(
    parameter DEPTH  = 64,
    parameter ADDR_W = 6
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             cap_start,
    input  wire             cap_stop,
    input  wire             play_start,
    input  wire             play_stop,
    input  wire [7:0]       period,
    input  wire             edge_mode,
    input  wire [1:0]       trig_pin,
    input  wire [7:0]       pins_in,
    output reg              capturing,
    output reg              playing,
    output reg              full,
    output wire [7:0]       pins_play,
    output wire [7:0]       oe_play,
    input  wire             host_re,
    output wire [7:0]       host_rdata,
    output wire [ADDR_W:0]  count
);
  reg [7:0] mem[0:DEPTH-1];
  reg [ADDR_W-1:0] wptr, rptr, play_ptr, host_ptr;
  reg [ADDR_W:0] nstored;
  reg [7:0] div;
  reg [7:0] period_r;
  reg armed;
  reg [7:0] last_pins;

  assign count = nstored;
  assign pins_play = playing ? mem[play_ptr] : 8'd0;
  assign oe_play = playing ? 8'hFF : 8'd0;
  assign host_rdata = mem[host_ptr];

  wire [7:0] trig_mask = 8'h01 << trig_pin;
  wire trig_now = edge_mode ? ((pins_in ^ last_pins) & trig_mask) != 8'd0 : 1'b1;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wptr       <= {ADDR_W{1'b0}};
      rptr       <= {ADDR_W{1'b0}};
      play_ptr   <= {ADDR_W{1'b0}};
      host_ptr   <= {ADDR_W{1'b0}};
      nstored    <= {(ADDR_W + 1) {1'b0}};
      div        <= 8'd0;
      period_r   <= 8'd0;
      capturing  <= 1'b0;
      playing    <= 1'b0;
      full       <= 1'b0;
      armed      <= 1'b0;
      last_pins  <= 8'd0;
    end else begin
      last_pins <= pins_in;

      if (cap_start) begin
        capturing <= 1'b1;
        playing   <= 1'b0;
        wptr      <= {ADDR_W{1'b0}};
        nstored   <= {(ADDR_W + 1) {1'b0}};
        full      <= 1'b0;
        div       <= 8'd0;
        period_r  <= period;
        armed     <= edge_mode;
        host_ptr  <= {ADDR_W{1'b0}};
      end
      if (cap_stop) capturing <= 1'b0;
      if (play_start) begin
        playing   <= 1'b1;
        capturing <= 1'b0;
        play_ptr  <= {ADDR_W{1'b0}};
        div       <= 8'd0;
        period_r  <= period;
      end
      if (play_stop) playing <= 1'b0;

      if (capturing && !full) begin
        if (armed) begin
          if (trig_now) armed <= 1'b0;
        end else if (div == period_r) begin
          div <= 8'd0;
          mem[wptr] <= pins_in;
          wptr <= wptr + 1'b1;
          if (nstored == DEPTH[ADDR_W:0]) full <= 1'b1;
          else nstored <= nstored + 1'b1;
        end else div <= div + 1'b1;
      end

      if (playing) begin
        if (div == period_r) begin
          div <= 8'd0;
          if (play_ptr == (nstored[ADDR_W-1:0] - 1'b1) || nstored == 0) begin
            playing <= 1'b0;
          end else play_ptr <= play_ptr + 1'b1;
        end else div <= div + 1'b1;
      end

      if (host_re && nstored != 0) begin
        if (host_ptr == nstored[ADDR_W-1:0] - 1'b1) host_ptr <= {ADDR_W{1'b0}};
        else host_ptr <= host_ptr + 1'b1;
      end
    end
  end
endmodule
