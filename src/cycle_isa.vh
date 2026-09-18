// Copyright (c) 2026 Narasinga Ujjini
// SPDX-License-Identifier: Apache-2.0
//
// Cycle ISA encoding. This file is the hardware copy of isa/encoding.py.
// Keep the two in lockstep; tests fail if they disagree.

`ifndef CYCLE_ISA_VH
`define CYCLE_ISA_VH

`define CYCLE_OP_JMP    4'h0
`define CYCLE_OP_WAIT   4'h1
`define CYCLE_OP_IN     4'h2
`define CYCLE_OP_OUT    4'h3
`define CYCLE_OP_MOV    4'h4
`define CYCLE_OP_SET    4'h5
`define CYCLE_OP_DELAY  4'h6
`define CYCLE_OP_FIFO   4'h7
`define CYCLE_OP_CRC    4'h8
`define CYCLE_OP_IRQ    4'h9
`define CYCLE_OP_CAP    4'hA
`define CYCLE_OP_PLAY   4'hB
`define CYCLE_OP_MODE   4'hC
`define CYCLE_OP_NRZI   4'hD
`define CYCLE_OP_PIN    4'hE
`define CYCLE_OP_HALT   4'hF

// JMP [11:9] condition
`define CYCLE_JC_ALWAYS 3'b000
`define CYCLE_JC_XEQ0   3'b001
`define CYCLE_JC_XDEC   3'b010
`define CYCLE_JC_YEQ0   3'b011
`define CYCLE_JC_YDEC   3'b100
`define CYCLE_JC_PIN    3'b101
`define CYCLE_JC_NPIN   3'b110
`define CYCLE_JC_OSRE   3'b111

// WAIT [10:8] source
`define CYCLE_WS_PIN    3'b000
`define CYCLE_WS_IRQ    3'b001
`define CYCLE_WS_RXRDY  3'b010
`define CYCLE_WS_TXRM   3'b011

// IN sources / OUT dests / MOV regs / SET dests share a 3-bit space where possible
`define CYCLE_R_PINS    3'b000
`define CYCLE_R_X       3'b001
`define CYCLE_R_Y       3'b010
`define CYCLE_R_PINDIRS 3'b011
`define CYCLE_R_ISR     3'b100
`define CYCLE_R_OSR     3'b101
`define CYCLE_R_CRC     3'b110
`define CYCLE_R_NULL    3'b111

`define CYCLE_SET_PINS     3'b000
`define CYCLE_SET_X        3'b001
`define CYCLE_SET_Y        3'b010
`define CYCLE_SET_PINDIRS  3'b011
`define CYCLE_SET_CLKDIV   3'b100
`define CYCLE_SET_OUTBASE  3'b101
`define CYCLE_SET_INBASE   3'b110
`define CYCLE_SET_JMPPIN   3'b111

`define CYCLE_OUT_PINS     3'b000
`define CYCLE_OUT_X        3'b001
`define CYCLE_OUT_Y        3'b010
`define CYCLE_OUT_PINDIRS  3'b011
`define CYCLE_OUT_PC       3'b100
`define CYCLE_OUT_ISR      3'b101
`define CYCLE_OUT_NULL     3'b110
`define CYCLE_OUT_PINSALL  3'b111

`define CYCLE_IN_PINS      3'b000
`define CYCLE_IN_X         3'b001
`define CYCLE_IN_Y         3'b010
`define CYCLE_IN_ISR       3'b011
`define CYCLE_IN_OSR       3'b100
`define CYCLE_IN_NULL      3'b101
`define CYCLE_IN_CRC       3'b110
`define CYCLE_IN_STATUS    3'b111

`define CYCLE_MOV_COPY     2'b00
`define CYCLE_MOV_NOT      2'b01
`define CYCLE_MOV_REV      2'b10
`define CYCLE_MOV_INC      2'b11

`define CYCLE_CRC_INIT     2'b00
`define CYCLE_CRC_OSR      2'b01
`define CYCLE_CRC_PINS     2'b10
`define CYCLE_CRC_TO_XY    2'b11

`define CYCLE_POLY_CRC8    2'b00
`define CYCLE_POLY_CCITT   2'b01
`define CYCLE_POLY_USB16   2'b10
`define CYCLE_POLY_CRC5    2'b11

`endif
