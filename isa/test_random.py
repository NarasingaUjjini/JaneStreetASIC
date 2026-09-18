# SPDX-License-Identifier: Apache-2.0
"""Constrained-random programs against the golden model."""

from __future__ import annotations

import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from isa.encoding import (
    OP_NAMES,
    enc_delay,
    enc_halt,
    enc_jmp,
    enc_pin,
    enc_set,
    enc_wait,
)
from isa.golden import CycleSM


def random_program(n: int, rng: random.Random) -> list[int]:
    words = []
    for i in range(n):
        kind = rng.randrange(6)
        if kind == 0:
            words.append(enc_set(rng.randrange(8), rng.randrange(256)))
        elif kind == 1:
            words.append(enc_delay(rng.randrange(4)))
        elif kind == 2:
            words.append(enc_pin(rng.randrange(8), rng.randrange(2), rng.randrange(2)))
        elif kind == 3:
            words.append(enc_jmp(rng.randrange(8), rng.randrange(n)))
        elif kind == 4:
            words.append(enc_wait(rng.randrange(2), 0, rng.randrange(8), rng.randrange(4)))
        else:
            words.append(enc_halt())
    return words


def test_random_programs_stay_in_range():
    rng = random.Random(2026)
    for trial in range(40):
        n = 16
        mem = random_program(n, rng) + [0] * (128 - n)
        sm = CycleSM()
        sm.halted = False
        pins = rng.randrange(256)
        for _ in range(80):
            sm.tick(mem, pins, 0, 0, 0, 1, True)
            assert 0 <= sm.pc < 128
            assert 0 <= sm.pins_out <= 255
            assert 0 <= sm.pindirs <= 255
            if sm.halted:
                pc = sm.pc
                sm.tick(mem, pins, 0, 0, 0, 1, True)
                assert sm.pc == pc
                break


def test_opcode_table_length():
    assert len(OP_NAMES) == 16
