// Copyright (c) 2026 Narasinga Ujjini
// SPDX-License-Identifier: Apache-2.0
`default_nettype none

`include "cycle_isa.vh"

module cycle_sm #(
    parameter ADDR_W = 7
) (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              running,
    input  wire              go,
    input  wire              set_pc,
    input  wire [ADDR_W-1:0] pc_in,
    output reg               halted,
    output wire [ADDR_W-1:0] imem_addr,
    input  wire [15:0]       imem_rdata,
    input  wire [7:0]        pins_in,
    output reg  [7:0]        pins_out,
    output reg  [7:0]        pins_oe,
    input  wire              tx_valid,
    input  wire [7:0]        tx_data,
    output reg               tx_ready,
    output reg               rx_valid,
    output reg  [7:0]        rx_data,
    input  wire              rx_ready,
    input  wire [3:0]        irq_in,
    output reg  [3:0]        irq_set,
    output reg  [3:0]        irq_clr,
    output reg               cap_start,
    output reg               cap_stop,
    output reg               play_start,
    output reg               play_stop,
    output reg  [7:0]        cap_period,
    output reg               cap_edge,
    output reg  [1:0]        cap_trig,
    output wire [7:0]        dbg_pc,
    output wire [7:0]        dbg_x
);
  reg [ADDR_W-1:0] pc;
  reg [7:0] x, y;
  reg [15:0] isr, osr;
  reg [4:0] isr_count, osr_count;
  reg [7:0] clkdiv, prescale;
  reg [2:0] out_base, in_base, jmp_pin;
  reg [11:0] delay_reg;
  reg [15:0] wait_count;
  reg wait_expired;
  reg [15:0] crc;
  reg [1:0] crc_poly_sel;
  reg osr_right, isr_left;
  reg nrzi_en, stuff_en;
  reg [2:0] ones_run;

  assign imem_addr = pc;
  assign dbg_pc = {{(8 - ADDR_W) {1'b0}}, pc};
  assign dbg_x = x;

  wire [15:0] word = imem_rdata;
  wire [3:0] op = word[15:12];
  wire [7:0] pin_mask_out = 8'h01 << out_base;
  wire pin_jmp = pins_in[jmp_pin];
  wire tick = running && !halted && (prescale == clkdiv);

  function automatic [15:0] crc_step8;
    input [15:0] crc_in;
    input [1:0] sel;
    input [7:0] din;
    integer i;
    reg [15:0] c;
    reg [15:0] poly;
    reg msb;
    reg b;
    begin
      case (sel)
        `CYCLE_POLY_CRC8:  poly = 16'h0007;
        `CYCLE_POLY_CCITT: poly = 16'h1021;
        `CYCLE_POLY_USB16: poly = 16'h8005;
        default:           poly = 16'h0005;
      endcase
      c = crc_in;
      for (i = 7; i >= 0; i = i - 1) begin
        b = din[i];
        case (sel)
          `CYCLE_POLY_CRC8:  msb = c[7];
          `CYCLE_POLY_CRC5:  msb = c[4];
          default:           msb = c[15];
        endcase
        c = c << 1;
        if (msb ^ b) c = c ^ poly;
      end
      crc_step8 = c;
    end
  endfunction

  reg out_bit;
  reg [7:0] tmp8;
  reg take;
  reg wait_ok;
  reg [3:0] in_cnt;
  reg [3:0] out_cnt;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc           <= {ADDR_W{1'b0}};
      x            <= 8'd0;
      y            <= 8'd0;
      isr          <= 16'd0;
      osr          <= 16'd0;
      isr_count    <= 5'd0;
      osr_count    <= 5'd0;
      pins_out     <= 8'd0;
      pins_oe      <= 8'd0;
      clkdiv       <= 8'd0;
      prescale     <= 8'd0;
      out_base     <= 3'd0;
      in_base      <= 3'd0;
      jmp_pin      <= 3'd0;
      halted       <= 1'b1;
      delay_reg    <= 12'd0;
      wait_count   <= 16'd0;
      wait_expired <= 1'b0;
      crc          <= 16'd0;
      crc_poly_sel <= 2'b01;
      osr_right    <= 1'b1;
      isr_left     <= 1'b1;
      nrzi_en      <= 1'b0;
      stuff_en     <= 1'b0;
      ones_run     <= 3'd0;
      tx_ready     <= 1'b0;
      rx_valid     <= 1'b0;
      rx_data      <= 8'd0;
      irq_set      <= 4'd0;
      irq_clr      <= 4'd0;
      cap_start    <= 1'b0;
      cap_stop     <= 1'b0;
      play_start   <= 1'b0;
      play_stop    <= 1'b0;
      cap_period   <= 8'd0;
      cap_edge     <= 1'b0;
      cap_trig     <= 2'd0;
    end else begin
      tx_ready   <= 1'b0;
      irq_set    <= 4'd0;
      irq_clr    <= 4'd0;
      cap_start  <= 1'b0;
      cap_stop   <= 1'b0;
      play_start <= 1'b0;
      play_stop  <= 1'b0;
      if (rx_valid && rx_ready) rx_valid <= 1'b0;

      if (set_pc) pc <= pc_in;
      if (go) halted <= 1'b0;

      if (!running || halted) prescale <= 8'd0;
      else if (prescale == clkdiv) prescale <= 8'd0;
      else prescale <= prescale + 1'b1;

      if (tick) begin
        if (delay_reg != 12'd0) begin
          delay_reg <= delay_reg - 1'b1;
        end else begin
          case (op)
            `CYCLE_OP_JMP: begin
              take = 1'b0;
              case (word[11:9])
                `CYCLE_JC_ALWAYS: take = 1'b1;
                `CYCLE_JC_XEQ0:   take = (x == 8'd0);
                `CYCLE_JC_XDEC: begin
                  take = (x != 8'd0);
                  if (x != 8'd0) x <= x - 8'd1;
                end
                `CYCLE_JC_YEQ0: take = (y == 8'd0);
                `CYCLE_JC_YDEC: begin
                  take = (y != 8'd0);
                  if (y != 8'd0) y <= y - 8'd1;
                end
                `CYCLE_JC_PIN:  take = pin_jmp;
                `CYCLE_JC_NPIN: take = ~pin_jmp;
                `CYCLE_JC_OSRE: take = (osr_count == 5'd0);
                default: take = 1'b0;
              endcase
              pc <= take ? word[ADDR_W-1:0] : (pc + 1'b1);
            end

            `CYCLE_OP_WAIT: begin
              wait_ok = 1'b0;
              case (word[10:8])
                `CYCLE_WS_PIN:   wait_ok = (pins_in[word[7:5]] == word[11]);
                `CYCLE_WS_IRQ:   wait_ok = (irq_in[word[6:5]] == word[11]);
                `CYCLE_WS_RXRDY: wait_ok = (rx_ready == word[11]);
                `CYCLE_WS_TXRM:  wait_ok = (tx_valid == word[11]);
                default: wait_ok = 1'b0;
              endcase
              if (wait_ok) begin
                wait_count <= 16'd0;
                pc <= pc + 1'b1;
              end else if (word[4:0] != 5'd0) begin
                wait_count <= wait_count + 1'b1;
                if (wait_count + 1'b1 >= (16'h0001 << word[4:0])) begin
                  wait_expired <= 1'b1;
                  wait_count   <= 16'd0;
                  pc           <= pc + 1'b1;
                end
              end
            end

            `CYCLE_OP_IN: begin
              in_cnt = (word[11:8] == 4'd0) ? 4'd8 : word[11:8];
              case (word[7:5])
                `CYCLE_IN_PINS: begin
                  if (in_cnt == 4'd1) begin
                    if (isr_left) isr <= {isr[14:0], pins_in[in_base]};
                    else isr <= {pins_in[in_base], isr[15:1]};
                    if (isr_count < 5'd16) isr_count <= isr_count + 1'b1;
                  end else begin
                    isr <= {isr[7:0], pins_in};
                    isr_count <= 5'd16;
                  end
                end
                `CYCLE_IN_X: begin
                  if (in_cnt == 4'd1) begin
                    if (isr_left) isr <= {isr[14:0], x[0]};
                    else isr <= {x[0], isr[15:1]};
                  end else isr <= {isr[7:0], x};
                end
                `CYCLE_IN_Y: begin
                  if (in_cnt == 4'd1) begin
                    if (isr_left) isr <= {isr[14:0], y[0]};
                    else isr <= {y[0], isr[15:1]};
                  end else isr <= {isr[7:0], y};
                end
                `CYCLE_IN_OSR: isr <= osr;
                `CYCLE_IN_NULL: begin
                  if (isr_left) isr <= {isr[14:0], 1'b0};
                  else isr <= {1'b0, isr[15:1]};
                end
                `CYCLE_IN_CRC:    isr <= crc;
                `CYCLE_IN_STATUS: isr <= {15'd0, wait_expired};
                default: ;
              endcase
              pc <= pc + 1'b1;
            end

            `CYCLE_OP_OUT: begin
              out_cnt = (word[11:8] == 4'd0) ? 4'd8 : word[11:8];
              out_bit = osr_right ? osr[0] : osr[15];
              case (word[7:5])
                `CYCLE_OUT_PINS: begin
                  if (out_cnt == 4'd1) begin
                    if (nrzi_en) begin
                      if (out_bit == 1'b0) pins_out <= pins_out ^ pin_mask_out;
                      else pins_out <= pins_out;
                      if (stuff_en) begin
                        if (out_bit == 1'b1) begin
                          if (ones_run >= 3'd5) begin
                            ones_run <= 3'd0;
                            pins_out <= pins_out ^ pin_mask_out;
                          end else ones_run <= ones_run + 1'b1;
                        end else ones_run <= 3'd0;
                      end
                    end else begin
                      if (out_bit) pins_out <= pins_out | pin_mask_out;
                      else pins_out <= pins_out & ~pin_mask_out;
                    end
                    if (osr_right) osr <= {1'b0, osr[15:1]};
                    else osr <= {osr[14:0], 1'b0};
                    if (osr_count != 0) osr_count <= osr_count - 1'b1;
                  end else begin
                    pins_out <= osr[7:0];
                    osr <= {8'd0, osr[15:8]};
                  end
                end
                `CYCLE_OUT_X: begin
                  if (out_cnt == 4'd1) begin
                    x <= {7'd0, out_bit};
                    if (osr_right) osr <= {1'b0, osr[15:1]};
                    else osr <= {osr[14:0], 1'b0};
                    if (osr_count != 0) osr_count <= osr_count - 1'b1;
                  end else begin
                    x <= osr[7:0];
                    osr <= {8'd0, osr[15:8]};
                  end
                end
                `CYCLE_OUT_Y: begin
                  if (out_cnt == 4'd1) begin
                    y <= {7'd0, out_bit};
                    if (osr_right) osr <= {1'b0, osr[15:1]};
                    else osr <= {osr[14:0], 1'b0};
                    if (osr_count != 0) osr_count <= osr_count - 1'b1;
                  end else begin
                    y <= osr[7:0];
                    osr <= {8'd0, osr[15:8]};
                  end
                end
                `CYCLE_OUT_PINDIRS: begin
                  pins_oe <= osr[7:0];
                  osr <= {8'd0, osr[15:8]};
                end
                `CYCLE_OUT_PC: begin
                  pc <= osr[ADDR_W-1:0];
                end
                `CYCLE_OUT_ISR: isr <= osr;
                `CYCLE_OUT_NULL: begin
                  if (osr_right) osr <= {1'b0, osr[15:1]};
                  else osr <= {osr[14:0], 1'b0};
                end
                `CYCLE_OUT_PINSALL: begin
                  pins_out <= osr[7:0];
                  osr <= {8'd0, osr[15:8]};
                end
                default: ;
              endcase
              if (word[7:5] != `CYCLE_OUT_PC) pc <= pc + 1'b1;
            end

            `CYCLE_OP_MOV: begin
              case (word[8:6])
                `CYCLE_R_PINS:    tmp8 = pins_in;
                `CYCLE_R_X:       tmp8 = x;
                `CYCLE_R_Y:       tmp8 = y;
                `CYCLE_R_PINDIRS: tmp8 = pins_oe;
                `CYCLE_R_ISR:     tmp8 = isr[7:0];
                `CYCLE_R_OSR:     tmp8 = osr[7:0];
                `CYCLE_R_CRC:     tmp8 = crc[7:0];
                default:          tmp8 = 8'd0;
              endcase
              case (word[5:4])
                `CYCLE_MOV_NOT: tmp8 = ~tmp8;
                `CYCLE_MOV_REV: begin
                  tmp8 = {tmp8[0], tmp8[1], tmp8[2], tmp8[3], tmp8[4], tmp8[5], tmp8[6], tmp8[7]};
                end
                `CYCLE_MOV_INC: tmp8 = tmp8 + 8'd1;
                default: ;
              endcase
              case (word[11:9])
                `CYCLE_R_PINS:    pins_out <= tmp8;
                `CYCLE_R_X:       x <= tmp8;
                `CYCLE_R_Y:       y <= tmp8;
                `CYCLE_R_PINDIRS: pins_oe <= tmp8;
                `CYCLE_R_ISR:     isr <= {8'd0, tmp8};
                `CYCLE_R_OSR: begin
                  osr <= {8'd0, tmp8};
                  osr_count <= 5'd8;
                end
                `CYCLE_R_CRC: crc <= {8'd0, tmp8};
                default: ;
              endcase
              pc <= pc + 1'b1;
            end

            `CYCLE_OP_SET: begin
              case (word[11:9])
                `CYCLE_SET_PINS:    pins_out <= word[7:0];
                `CYCLE_SET_X:       x <= word[7:0];
                `CYCLE_SET_Y:       y <= word[7:0];
                `CYCLE_SET_PINDIRS: pins_oe <= word[7:0];
                `CYCLE_SET_CLKDIV:  clkdiv <= word[7:0];
                `CYCLE_SET_OUTBASE: out_base <= word[2:0];
                `CYCLE_SET_INBASE:  in_base <= word[2:0];
                `CYCLE_SET_JMPPIN:  jmp_pin <= word[2:0];
                default: ;
              endcase
              pc <= pc + 1'b1;
            end

            `CYCLE_OP_DELAY: begin
              if (word[11:0] != 12'd0) delay_reg <= word[11:0];
              pc <= pc + 1'b1;
            end

            `CYCLE_OP_FIFO: begin
              if (word[11]) begin
                if (tx_valid) begin
                  osr <= {8'd0, tx_data};
                  osr_count <= 5'd8;
                  tx_ready <= 1'b1;
                  pc <= pc + 1'b1;
                end else if (word[10]) pc <= pc + 1'b1;
              end else begin
                if (rx_ready && !(rx_valid && !rx_ready)) begin
                  rx_data  <= isr[7:0];
                  rx_valid <= 1'b1;
                  isr <= 16'd0;
                  isr_count <= 5'd0;
                  pc <= pc + 1'b1;
                end else if (word[10]) pc <= pc + 1'b1;
              end
            end

            `CYCLE_OP_CRC: begin
              crc_poly_sel <= word[9:8];
              case (word[11:10])
                `CYCLE_CRC_INIT: crc <= (word[9:8] == `CYCLE_POLY_CRC8) ? {8'd0, word[7:0]} :
                                        (word[7:0] == 8'd0) ? 16'hFFFF : {8'd0, word[7:0]};
                `CYCLE_CRC_OSR:  crc <= crc_step8(crc, word[9:8], osr[7:0]);
                `CYCLE_CRC_PINS: crc <= crc_step8(crc, word[9:8], pins_in);
                `CYCLE_CRC_TO_XY: begin
                  x <= crc[7:0];
                  y <= crc[15:8];
                end
                default: ;
              endcase
              pc <= pc + 1'b1;
            end

            `CYCLE_OP_IRQ: begin
              if (word[11]) begin
                if (irq_in[word[9:8]]) begin
                  if (word[10]) irq_clr <= (4'b0001 << word[9:8]);
                  pc <= pc + 1'b1;
                end
              end else begin
                if (word[10]) irq_clr <= (4'b0001 << word[9:8]);
                else irq_set <= (4'b0001 << word[9:8]);
                pc <= pc + 1'b1;
              end
            end

            `CYCLE_OP_CAP: begin
              cap_edge   <= word[10];
              cap_trig   <= word[9:8];
              cap_period <= word[7:0];
              if (word[11]) cap_start <= 1'b1;
              else cap_stop <= 1'b1;
              pc <= pc + 1'b1;
            end

            `CYCLE_OP_PLAY: begin
              cap_period <= word[7:0];
              if (word[11]) play_start <= 1'b1;
              else play_stop <= 1'b1;
              pc <= pc + 1'b1;
            end

            `CYCLE_OP_MODE: begin
              osr_right <= word[11];
              isr_left  <= word[10];
              pc <= pc + 1'b1;
            end

            `CYCLE_OP_NRZI: begin
              nrzi_en  <= word[11];
              stuff_en <= word[10];
              ones_run <= 3'd0;
              pc <= pc + 1'b1;
            end

            `CYCLE_OP_PIN: begin
              if (word[6]) pins_oe <= pins_oe | (8'h01 << word[10:8]);
              else pins_oe <= pins_oe & ~(8'h01 << word[10:8]);
              if (word[7]) pins_out <= pins_out | (8'h01 << word[10:8]);
              else pins_out <= pins_out & ~(8'h01 << word[10:8]);
              pc <= pc + 1'b1;
            end

            `CYCLE_OP_HALT: halted <= 1'b1;

            default: pc <= pc + 1'b1;
          endcase
        end
      end
    end
  end
endmodule
