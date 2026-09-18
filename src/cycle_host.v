// Copyright (c) 2026 Narasinga Ujjini
// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// UART command processor. Frames are 0xA5, cmd, payload...
// CMD_WMEM  0x01  addr, lo, hi     write one instruction word
// CMD_RUN   0x02                   start both state machines
// CMD_HALT  0x03                   stop
// CMD_WFIFO 0x04  data             byte into SM0 TX FIFO
// CMD_RFIFO 0x05                   pop SM0 RX FIFO, send it back
// CMD_STAT  0x06                   send status byte
// CMD_SETPC 0x07  sm, pc           set PC (sm=0/1)
// CMD_CAPON 0x09
// CMD_CAPOFF 0x0A
// CMD_CAPRD 0x0B                   send one capture sample
// CMD_PLAY  0x0C

module cycle_host (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_valid,
    input  wire [7:0] rx_data,
    output reg        rx_ready,
    output reg        tx_we,
    output reg  [7:0] tx_data,
    input  wire       tx_busy,
    output reg        mem_we,
    output reg  [6:0] mem_addr,
    output reg  [15:0] mem_wdata,
    output reg        running,
    output reg        go0,
    output reg        go1,
    output reg        set_pc0,
    output reg        set_pc1,
    output reg  [6:0] pc_val,
    output reg        fifo_we,
    output reg  [7:0] fifo_wdata,
    input  wire       fifo_full,
    output reg        fifo_re,
    input  wire [7:0] fifo_rdata,
    input  wire       fifo_empty,
    input  wire       sm0_halted,
    input  wire       sm1_halted,
    input  wire       capturing,
    input  wire       playing,
    output reg        cap_start,
    output reg        cap_stop,
    output reg        play_start,
    input  wire [7:0] cap_rdata,
    output reg        cap_re
);
  localparam [3:0] ST_MAGIC = 4'd0;
  localparam [3:0] ST_CMD   = 4'd1;
  localparam [3:0] ST_A     = 4'd2;
  localparam [3:0] ST_B     = 4'd3;
  localparam [3:0] ST_C     = 4'd4;
  localparam [3:0] ST_REPLY = 4'd5;

  localparam [7:0] C_WMEM  = 8'h01;
  localparam [7:0] C_RUN   = 8'h02;
  localparam [7:0] C_HALT  = 8'h03;
  localparam [7:0] C_WFIFO = 8'h04;
  localparam [7:0] C_RFIFO = 8'h05;
  localparam [7:0] C_STAT  = 8'h06;
  localparam [7:0] C_SETPC = 8'h07;
  localparam [7:0] C_CAPON = 8'h09;
  localparam [7:0] C_CAPOFF= 8'h0A;
  localparam [7:0] C_CAPRD = 8'h0B;
  localparam [7:0] C_PLAY  = 8'h0C;
  localparam [7:0] C_RUN1  = 8'h0E;

  reg [3:0] st;
  reg [7:0] cmd, a, b;
  reg [7:0] reply;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st         <= ST_MAGIC;
      cmd        <= 8'd0;
      a          <= 8'd0;
      b          <= 8'd0;
      reply      <= 8'd0;
      rx_ready   <= 1'b1;
      tx_we      <= 1'b0;
      tx_data    <= 8'd0;
      mem_we     <= 1'b0;
      mem_addr   <= 7'd0;
      mem_wdata  <= 16'd0;
      running    <= 1'b0;
      go0        <= 1'b0;
      go1        <= 1'b0;
      set_pc0    <= 1'b0;
      set_pc1    <= 1'b0;
      pc_val     <= 7'd0;
      fifo_we    <= 1'b0;
      fifo_wdata <= 8'd0;
      fifo_re    <= 1'b0;
      cap_start  <= 1'b0;
      cap_stop   <= 1'b0;
      play_start <= 1'b0;
      cap_re     <= 1'b0;
    end else begin
      mem_we     <= 1'b0;
      tx_we      <= 1'b0;
      go0        <= 1'b0;
      go1        <= 1'b0;
      set_pc0    <= 1'b0;
      set_pc1    <= 1'b0;
      fifo_we    <= 1'b0;
      fifo_re    <= 1'b0;
      cap_start  <= 1'b0;
      cap_stop   <= 1'b0;
      play_start <= 1'b0;
      cap_re     <= 1'b0;
      rx_ready   <= 1'b1;

      case (st)
        ST_MAGIC: if (rx_valid && rx_data == 8'hA5) st <= ST_CMD;
        ST_CMD: if (rx_valid) begin
          cmd <= rx_data;
          case (rx_data)
            C_RUN: begin
              running <= 1'b1;
              go0     <= 1'b1;
              go1     <= 1'b0;  // SM1 stays halted unless SETPC+explicit go
              st      <= ST_MAGIC;
            end
            C_HALT: begin
              running <= 1'b0;
              st      <= ST_MAGIC;
            end
            C_STAT: begin
              reply <= {playing, capturing, sm1_halted, sm0_halted,
                        fifo_empty, fifo_full, running, 1'b1};
              st    <= ST_REPLY;
            end
            C_CAPON: begin
              cap_start <= 1'b1;
              st <= ST_MAGIC;
            end
            C_CAPOFF: begin
              cap_stop <= 1'b1;
              st <= ST_MAGIC;
            end
            C_PLAY: begin
              play_start <= 1'b1;
              st <= ST_MAGIC;
            end
            C_RUN1: begin
              running <= 1'b1;
              go1     <= 1'b1;
              st      <= ST_MAGIC;
            end
            C_RFIFO: begin
              if (!fifo_empty) begin
                fifo_re <= 1'b1;
                reply   <= fifo_rdata;
                st      <= ST_REPLY;
              end else begin
                reply <= 8'hFF;
                st    <= ST_REPLY;
              end
            end
            C_CAPRD: begin
              cap_re <= 1'b1;
              reply  <= cap_rdata;
              st     <= ST_REPLY;
            end
            default: st <= ST_A;
          endcase
        end
        ST_A: if (rx_valid) begin
          a <= rx_data;
          if (cmd == C_WFIFO) begin
            fifo_wdata <= rx_data;
            fifo_we    <= ~fifo_full;
            st         <= ST_MAGIC;
          end else st <= ST_B;
        end
        ST_B: if (rx_valid) begin
          b <= rx_data;
          if (cmd == C_SETPC) begin
            pc_val <= rx_data[6:0];
            if (a[0] == 1'b0) set_pc0 <= 1'b1;
            else set_pc1 <= 1'b1;
            st <= ST_MAGIC;
          end else st <= ST_C;
        end
        ST_C: if (rx_valid) begin
          if (cmd == C_WMEM) begin
            mem_addr  <= a[6:0];
            mem_wdata <= {rx_data, b};
            mem_we    <= 1'b1;
          end
          st <= ST_MAGIC;
        end
        ST_REPLY: if (!tx_busy) begin
          tx_we   <= 1'b1;
          tx_data <= reply;
          st      <= ST_MAGIC;
        end
        default: st <= ST_MAGIC;
      endcase
    end
  end
endmodule
