# SPDX-License-Identifier: Apache-2.0
"""Golden-model tests. No simulator required."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from fw.programs import uart_tx
from isa.encoding import (
    JC_ALWAYS,
    JC_XDEC,
    OP_DELAY,
    OP_SET,
    SET_X,
    decode_op,
    enc_delay,
    enc_jmp,
    enc_set,
)
from isa.golden import CycleSM


def test_delay_takes_n_plus_one_ticks():
    mem = [enc_delay(3), enc_set(SET_X, 1)] + [0] * 126
    sm = CycleSM()
    sm.halted = False
    for _ in range(4):
        sm.tick(mem, 0, 0, 0, 0, 1, True)
        assert sm.x == 0
    sm.tick(mem, 0, 0, 0, 0, 1, True)
    assert sm.x == 1


def test_xdec_loops_eight_times():
    mem = [enc_set(SET_X, 7), enc_jmp(JC_XDEC, 1), enc_set(SET_X, 99)] + [0] * 125
    sm = CycleSM()
    sm.halted = False
    sm.tick(mem, 0, 0, 0, 0, 1, True)  # SET X,7
    loops = 0
    for _ in range(20):
        sm.tick(mem, 0, 0, 0, 0, 1, True)
        loops += 1
        if sm.x == 99:
            break
    assert loops == 9  # 8 JMP ticks + the SET X,99


def test_uart_tx_program_emits_0x55():
    mem = uart_tx(baud_div=0) + [0] * 64
    sm = CycleSM()
    sm.halted = False
    tx_valid = 1
    tx_data = 0x55
    start = False
    data_bits = []
    for _ in range(80):
        prev = (sm.pins_out & 1) if (sm.pindirs & 1) else 1
        sm.tick(mem, 0, 0, tx_valid, tx_data, 1, True)
        if sm.tx_ready_pulse:
            tx_valid = 0
        bit = (sm.pins_out & 1) if (sm.pindirs & 1) else 1
        # Data OUTs live at pc==9 after execute (instr 8 is OUT, pc increments).
        if not start and prev == 1 and bit == 0:
            start = True
            continue
        if start and sm.pc == 9:
            data_bits.append(bit)
            if len(data_bits) == 8:
                break
    assert start
    value = 0
    for i, b in enumerate(data_bits):
        value |= b << i
    assert value == 0x55, data_bits


def test_encoding_roundtrip_halt():
    from isa.encoding import enc_halt

    w = enc_halt()
    assert decode_op(w) == 0xF
