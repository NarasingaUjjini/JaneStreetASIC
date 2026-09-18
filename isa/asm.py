# Copyright (c) 2026 Narasinga Ujjini
# SPDX-License-Identifier: Apache-2.0
"""Tiny assembler for Cycle firmware.

Example:
    from isa.asm import Assembler
    a = Assembler()
    a.set(SET_PINDIRS, 0x01)
    a.pin(0, 1, 1)
    a.halt()
    words = a.words()
"""

from __future__ import annotations

from isa.encoding import (
    JC_ALWAYS,
    MOV_COPY,
    POLY_CCITT,
    SET_X,
    enc_cap,
    enc_crc,
    enc_delay,
    enc_fifo,
    enc_halt,
    enc_in,
    enc_irq,
    enc_jmp,
    enc_mode,
    enc_mov,
    enc_nrzi,
    enc_out,
    enc_pin,
    enc_play,
    enc_set,
    enc_wait,
)


class Assembler:
    def __init__(self):
        self._words: list[int] = []
        self.labels: dict[str, int] = {}
        self._fixups: list[tuple[int, str, int]] = []  # index, label, cond

    def here(self) -> int:
        return len(self._words)

    def label(self, name: str) -> None:
        self.labels[name] = self.here()

    def emit(self, word: int) -> int:
        self._words.append(word & 0xFFFF)
        return len(self._words) - 1

    def jmp(self, cond, addr=None, label=None):
        if label is not None:
            idx = self.emit(enc_jmp(cond, 0))
            self._fixups.append((idx, label, cond))
            return idx
        return self.emit(enc_jmp(cond, addr or 0))

    def jmp_always(self, label=None, addr=None):
        return self.jmp(JC_ALWAYS, addr=addr, label=label)

    def wait(self, polarity, src, index, timeout_exp=0):
        return self.emit(enc_wait(polarity, src, index, timeout_exp))

    def inn(self, count, src):
        return self.emit(enc_in(count, src))

    def out(self, count, dest):
        return self.emit(enc_out(count, dest))

    def mov(self, dest, src, op=MOV_COPY):
        return self.emit(enc_mov(dest, src, op))

    def set(self, dest, imm):
        return self.emit(enc_set(dest, imm))

    def delay(self, cycles):
        return self.emit(enc_delay(cycles))

    def pull(self, iff=0):
        return self.emit(enc_fifo(pull=1, iff=iff))

    def push(self, iff=0):
        return self.emit(enc_fifo(pull=0, iff=iff))

    def crc(self, cmd, poly=POLY_CCITT, imm=0):
        return self.emit(enc_crc(cmd, poly, imm))

    def irq(self, wait=0, clear=0, index=0):
        return self.emit(enc_irq(wait, clear, index))

    def cap(self, start, edge=0, trig_pin=0, period=0):
        return self.emit(enc_cap(start, edge, trig_pin, period))

    def play(self, start, period=0):
        return self.emit(enc_play(start, period))

    def mode(self, **kwargs):
        return self.emit(enc_mode(**kwargs))

    def nrzi(self, enable, stuff=0):
        return self.emit(enc_nrzi(enable, stuff))

    def pin(self, index, value, oe):
        return self.emit(enc_pin(index, value, oe))

    def halt(self):
        return self.emit(enc_halt())

    def words(self) -> list[int]:
        for idx, label, cond in self._fixups:
            if label not in self.labels:
                raise KeyError(f"undefined label {label}")
            self._words[idx] = enc_jmp(cond, self.labels[label])
        return list(self._words)

    def hex_lines(self) -> str:
        return "\n".join(f"{w:04x}" for w in self.words()) + "\n"
