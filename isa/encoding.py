# Copyright (c) 2026 Narasinga Ujjini
# SPDX-License-Identifier: Apache-2.0
"""Cycle ISA encoding. Must match src/cycle_isa.vh exactly."""

OP_JMP = 0x0
OP_WAIT = 0x1
OP_IN = 0x2
OP_OUT = 0x3
OP_MOV = 0x4
OP_SET = 0x5
OP_DELAY = 0x6
OP_FIFO = 0x7
OP_CRC = 0x8
OP_IRQ = 0x9
OP_CAP = 0xA
OP_PLAY = 0xB
OP_MODE = 0xC
OP_NRZI = 0xD
OP_PIN = 0xE
OP_HALT = 0xF

OP_NAMES = [
    "JMP", "WAIT", "IN", "OUT", "MOV", "SET", "DELAY", "FIFO",
    "CRC", "IRQ", "CAP", "PLAY", "MODE", "NRZI", "PIN", "HALT",
]

JC_ALWAYS, JC_XEQ0, JC_XDEC, JC_YEQ0, JC_YDEC, JC_PIN, JC_NPIN, JC_OSRE = range(8)
JC_NAMES = ["ALWAYS", "XEQ0", "XDEC", "YEQ0", "YDEC", "PIN", "NPIN", "OSRE"]

WS_PIN, WS_IRQ, WS_RXRDY, WS_TXRM = range(4)

R_PINS, R_X, R_Y, R_PINDIRS, R_ISR, R_OSR, R_CRC, R_NULL = range(8)
SET_PINS, SET_X, SET_Y, SET_PINDIRS, SET_CLKDIV, SET_OUTBASE, SET_INBASE, SET_JMPPIN = range(8)
OUT_PINS, OUT_X, OUT_Y, OUT_PINDIRS, OUT_PC, OUT_ISR, OUT_NULL, OUT_PINSALL = range(8)
IN_PINS, IN_X, IN_Y, IN_ISR, IN_OSR, IN_NULL, IN_CRC, IN_STATUS = range(8)

MOV_COPY, MOV_NOT, MOV_REV, MOV_INC = range(4)
CRC_INIT, CRC_OSR, CRC_PINS, CRC_TO_XY = range(4)
POLY_CRC8, POLY_CCITT, POLY_USB16, POLY_CRC5 = range(4)

# Polynomials (bitwise, MSB-first byte update)
POLY_TAPS = {
    POLY_CRC8: 0x07,
    POLY_CCITT: 0x1021,
    POLY_USB16: 0x8005,
    POLY_CRC5: 0x05,
}


def _u(n, w):
    return n & ((1 << w) - 1)


def enc_jmp(cond, addr):
    return (_u(OP_JMP, 4) << 12) | (_u(cond, 3) << 9) | _u(addr, 9)


def enc_wait(polarity, src, index, timeout_exp=0):
    return (
        (OP_WAIT << 12)
        | (_u(polarity, 1) << 11)
        | (_u(src, 3) << 8)
        | (_u(index, 3) << 5)
        | _u(timeout_exp, 5)
    )


def enc_in(count, src):
    """count 1..16; 16 is encoded as 0."""
    c = 0 if count == 16 else _u(count, 4)
    return (OP_IN << 12) | (c << 8) | (_u(src, 3) << 5)


def enc_out(count, dest):
    c = 0 if count == 16 else _u(count, 4)
    return (OP_OUT << 12) | (c << 8) | (_u(dest, 3) << 5)


def enc_mov(dest, src, op=MOV_COPY):
    return (OP_MOV << 12) | (_u(dest, 3) << 9) | (_u(src, 3) << 6) | (_u(op, 2) << 4)


def enc_set(dest, imm):
    return (OP_SET << 12) | (_u(dest, 3) << 9) | _u(imm, 9)


def enc_delay(cycles):
    """Takes (cycles+1) ticks. cycles is 0..4095."""
    return (OP_DELAY << 12) | _u(cycles, 12)


def enc_fifo(pull, iff=0):
    """pull=1: TX fifo -> OSR. pull=0: ISR -> RX fifo."""
    return (OP_FIFO << 12) | (_u(pull, 1) << 11) | (_u(iff, 1) << 10)


def enc_crc(cmd, poly=POLY_CCITT, imm=0):
    return (OP_CRC << 12) | (_u(cmd, 2) << 10) | (_u(poly, 2) << 8) | _u(imm, 8)


def enc_irq(wait, clear, index):
    return (OP_IRQ << 12) | (_u(wait, 1) << 11) | (_u(clear, 1) << 10) | (_u(index, 2) << 8)


def enc_cap(start, edge=0, trig_pin=0, period=0):
    return (
        (OP_CAP << 12)
        | (_u(start, 1) << 11)
        | (_u(edge, 1) << 10)
        | (_u(trig_pin, 2) << 8)
        | _u(period, 8)
    )


def enc_play(start, period=0):
    return (OP_PLAY << 12) | (_u(start, 1) << 11) | _u(period, 11)


def enc_mode(osr_right=1, isr_left=1, autopush=0, autopull=0, thresh=8):
    return (
        (OP_MODE << 12)
        | (_u(osr_right, 1) << 11)
        | (_u(isr_left, 1) << 10)
        | (_u(autopush, 1) << 9)
        | (_u(autopull, 1) << 8)
        | (_u(thresh, 5) << 3)
    )


def enc_nrzi(enable, stuff=0):
    return (OP_NRZI << 12) | (_u(enable, 1) << 11) | (_u(stuff, 1) << 10)


def enc_pin(index, value, oe):
    return (OP_PIN << 12) | (_u(index, 3) << 8) | (_u(value, 1) << 7) | (_u(oe, 1) << 6)


def enc_halt():
    return OP_HALT << 12


def decode_op(word):
    return (word >> 12) & 0xF


def bitrev8(x):
    y = 0
    for i in range(8):
        if x & (1 << i):
            y |= 1 << (7 - i)
    return y
