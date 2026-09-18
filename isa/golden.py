# Copyright (c) 2026 Narasinga Ujjini
# SPDX-License-Identifier: Apache-2.0
"""
Cycle golden model.

One call to tick() is one state-machine tick (after the clock divider).
If RTL and this model disagree, RTL is wrong — this file is the spec.
"""

from __future__ import annotations

from isa.encoding import (
    CRC_INIT,
    CRC_OSR,
    CRC_PINS,
    CRC_TO_XY,
    IN_CRC,
    IN_ISR,
    IN_NULL,
    IN_OSR,
    IN_PINS,
    IN_STATUS,
    IN_X,
    IN_Y,
    JC_ALWAYS,
    JC_NPIN,
    JC_OSRE,
    JC_PIN,
    JC_XDEC,
    JC_XEQ0,
    JC_YDEC,
    JC_YEQ0,
    MOV_COPY,
    MOV_INC,
    MOV_NOT,
    MOV_REV,
    OP_CAP,
    OP_CRC,
    OP_DELAY,
    OP_FIFO,
    OP_HALT,
    OP_IN,
    OP_IRQ,
    OP_JMP,
    OP_MODE,
    OP_MOV,
    OP_NRZI,
    OP_OUT,
    OP_PIN,
    OP_PLAY,
    OP_SET,
    OP_WAIT,
    OUT_ISR,
    OUT_NULL,
    OUT_PC,
    OUT_PINS,
    OUT_PINSALL,
    OUT_PINDIRS,
    OUT_X,
    OUT_Y,
    POLY_CCITT,
    POLY_CRC5,
    POLY_CRC8,
    POLY_USB16,
    R_CRC,
    R_ISR,
    R_NULL,
    R_OSR,
    R_PINS,
    R_PINDIRS,
    R_X,
    R_Y,
    SET_CLKDIV,
    SET_INBASE,
    SET_JMPPIN,
    SET_OUTBASE,
    SET_PINS,
    SET_PINDIRS,
    SET_X,
    SET_Y,
    WS_IRQ,
    WS_PIN,
    WS_RXRDY,
    WS_TXRM,
    bitrev8,
    decode_op,
)


def _crc_update_msb(crc: int, width: int, poly: int, data: int, nbits: int) -> int:
    mask = (1 << width) - 1
    crc &= mask
    for i in range(nbits - 1, -1, -1):
        bit = (data >> i) & 1
        msb = (crc >> (width - 1)) & 1
        crc = ((crc << 1) & mask)
        if msb ^ bit:
            crc ^= poly
    return crc


class CycleSM:
    def __init__(self, addr_bits: int = 7):
        self.addr_bits = addr_bits
        self.addr_mask = (1 << addr_bits) - 1
        self.reset()

    def reset(self) -> None:
        self.pc = 0
        self.x = 0
        self.y = 0
        self.isr = 0
        self.osr = 0
        self.isr_count = 0
        self.osr_count = 0
        self.pindirs = 0
        self.pins_out = 0
        self.clkdiv = 0
        self.prescale = 0
        self.out_base = 0
        self.in_base = 0
        self.jmp_pin = 0
        self.halted = True
        self.delay_reg = 0
        self.wait_count = 0
        self.wait_expired = 0
        self.crc = 0
        self.crc_poly_sel = POLY_CCITT
        self.osr_right = 1
        self.isr_left = 1
        self.autopush = 0
        self.autopull = 0
        self.thresh = 8
        self.nrzi_en = 0
        self.stuff_en = 0
        self.ones_run = 0
        self.irq_out_set = 0
        self.irq_out_clr = 0
        self.cap_cmd = 0  # 0 idle, 1 start, 2 stop
        self.play_cmd = 0
        self.cap_period = 0
        self.play_period = 0
        self.cap_edge = 0
        self.cap_trig = 0
        self.tx_ready_pulse = 0
        self.rx_valid_pulse = 0
        self.rx_data = 0
        self.stalled = False

    def running_tick(self, running: bool) -> bool:
        """Return True if this sysclk is an SM tick."""
        if not running or self.halted:
            self.prescale = 0
            return False
        if self.prescale == self.clkdiv:
            self.prescale = 0
            return True
        self.prescale = (self.prescale + 1) & 0xFF
        return False

    def _read_reg(self, sel: int, pins_in: int, status: int) -> int:
        return {
            R_PINS: pins_in & 0xFF,
            R_X: self.x,
            R_Y: self.y,
            R_PINDIRS: self.pindirs,
            R_ISR: self.isr & 0xFFFF,
            R_OSR: self.osr & 0xFFFF,
            R_CRC: self.crc & 0xFFFF,
            R_NULL: 0,
        }[sel]

    def _write_reg(self, sel: int, val: int) -> None:
        val8 = val & 0xFF
        val16 = val & 0xFFFF
        if sel == R_PINS:
            self.pins_out = val8
        elif sel == R_X:
            self.x = val8
        elif sel == R_Y:
            self.y = val8
        elif sel == R_PINDIRS:
            self.pindirs = val8
        elif sel == R_ISR:
            self.isr = val16
        elif sel == R_OSR:
            self.osr = val16
            self.osr_count = 16
        elif sel == R_CRC:
            self.crc = val16

    def _shift_out_bit(self) -> int:
        if self.osr_right:
            bit = self.osr & 1
            self.osr = (self.osr >> 1) & 0xFFFF
        else:
            bit = (self.osr >> 15) & 1
            self.osr = (self.osr << 1) & 0xFFFF
        if self.osr_count:
            self.osr_count -= 1
        return bit

    def _shift_in_bit(self, bit: int) -> None:
        if self.isr_left:
            self.isr = ((self.isr << 1) | (bit & 1)) & 0xFFFF
        else:
            self.isr = ((self.isr >> 1) | ((bit & 1) << 15)) & 0xFFFF
        if self.isr_count < 16:
            self.isr_count += 1

    def _drive_bit(self, bit: int) -> None:
        mask = 1 << (self.out_base & 7)
        if self.nrzi_en:
            if bit == 0:
                self.pins_out ^= mask
            if self.stuff_en:
                if bit == 1:
                    self.ones_run += 1
                    if self.ones_run >= 6:
                        self.ones_run = 0
                        self.pins_out ^= mask  # inserted 0 = extra transition
                else:
                    self.ones_run = 0
        else:
            if bit:
                self.pins_out |= mask
            else:
                self.pins_out &= ~mask

    def _poly_width(self, sel: int) -> tuple[int, int]:
        if sel == POLY_CRC8:
            return 8, 0x07
        if sel == POLY_CCITT:
            return 16, 0x1021
        if sel == POLY_USB16:
            return 16, 0x8005
        return 5, 0x05

    def tick(
        self,
        mem: list[int],
        pins_in: int,
        irq: int,
        tx_valid: int,
        tx_data: int,
        rx_ready: int,
        running: bool,
    ) -> None:
        """Advance one SM tick. Memory is a list of 16-bit words."""
        self.tx_ready_pulse = 0
        self.rx_valid_pulse = 0
        self.irq_out_set = 0
        self.irq_out_clr = 0
        self.cap_cmd = 0
        self.play_cmd = 0
        self.stalled = False

        if not running or self.halted:
            return

        word = mem[self.pc & self.addr_mask]
        op = decode_op(word)

        if self.delay_reg:
            self.delay_reg -= 1
            return

        if op == OP_JMP:
            cond = (word >> 9) & 7
            addr = word & 0x1FF
            take = False
            pin = (pins_in >> (self.jmp_pin & 7)) & 1
            if cond == JC_ALWAYS:
                take = True
            elif cond == JC_XEQ0:
                take = self.x == 0
            elif cond == JC_XDEC:
                take = self.x != 0
                if take:
                    self.x = (self.x - 1) & 0xFF
            elif cond == JC_YEQ0:
                take = self.y == 0
            elif cond == JC_YDEC:
                take = self.y != 0
                if take:
                    self.y = (self.y - 1) & 0xFF
            elif cond == JC_PIN:
                take = pin == 1
            elif cond == JC_NPIN:
                take = pin == 0
            elif cond == JC_OSRE:
                take = self.osr_count == 0
            self.pc = (addr if take else self.pc + 1) & self.addr_mask
            return

        if op == OP_WAIT:
            pol = (word >> 11) & 1
            src = (word >> 8) & 7
            index = (word >> 5) & 7
            texp = word & 0x1F
            ok = False
            if src == WS_PIN:
                ok = ((pins_in >> (index & 7)) & 1) == pol
            elif src == WS_IRQ:
                ok = ((irq >> (index & 3)) & 1) == pol
            elif src == WS_RXRDY:
                ok = (rx_ready == 1) == (pol == 1)  # pol=1 wait until host can take
            elif src == WS_TXRM:
                ok = (tx_valid == 1) == (pol == 1)
            if ok:
                self.wait_count = 0
                self.pc = (self.pc + 1) & self.addr_mask
                return
            if texp:
                self.wait_count += 1
                if self.wait_count >= (1 << texp):
                    self.wait_expired = 1
                    self.wait_count = 0
                    self.pc = (self.pc + 1) & self.addr_mask
                    return
            self.stalled = True
            return

        if op == OP_IN:
            raw_c = (word >> 8) & 0xF
            count = 16 if raw_c == 0 else raw_c
            src = (word >> 5) & 7
            status = (
                (self.wait_expired & 1)
                | ((tx_valid & 1) << 1)
                | ((rx_ready & 1) << 2)
                | ((self.halted & 1) << 3)
            )
            if src == IN_PINS:
                if count == 1:
                    self._shift_in_bit((pins_in >> (self.in_base & 7)) & 1)
                else:
                    self.isr = ((self.isr << 8) | (pins_in & 0xFF)) & 0xFFFF
                    self.isr_count = min(16, self.isr_count + 8)
            elif src == IN_X:
                self._shift_in_bit((self.x >> 0) & 1) if count == 1 else None
                if count != 1:
                    self.isr = ((self.isr << 8) | self.x) & 0xFFFF
            elif src == IN_Y:
                if count == 1:
                    self._shift_in_bit(self.y & 1)
                else:
                    self.isr = ((self.isr << 8) | self.y) & 0xFFFF
            elif src == IN_ISR:
                pass
            elif src == IN_OSR:
                self.isr = self.osr
            elif src == IN_NULL:
                for _ in range(min(count, 16)):
                    self._shift_in_bit(0)
            elif src == IN_CRC:
                self.isr = self.crc & 0xFFFF
            elif src == IN_STATUS:
                self.isr = status
            self.pc = (self.pc + 1) & self.addr_mask
            return

        if op == OP_OUT:
            raw_c = (word >> 8) & 0xF
            count = 16 if raw_c == 0 else raw_c
            dest = (word >> 5) & 7
            if dest == OUT_PINS:
                n = 1 if count == 1 else min(count, 8)
                if n == 1:
                    self._drive_bit(self._shift_out_bit())
                else:
                    bits = 0
                    for i in range(n):
                        bits |= self._shift_out_bit() << i
                    self.pins_out = bits & 0xFF
            elif dest == OUT_X:
                self.x = self._shift_out_bit() if count == 1 else (self.osr & 0xFF)
                if count != 1:
                    self.osr = (self.osr >> 8) & 0xFFFF
            elif dest == OUT_Y:
                self.y = self._shift_out_bit() if count == 1 else (self.osr & 0xFF)
                if count != 1:
                    self.osr = (self.osr >> 8) & 0xFFFF
            elif dest == OUT_PINDIRS:
                self.pindirs = self.osr & 0xFF
                self.osr = (self.osr >> 8) & 0xFFFF
            elif dest == OUT_PC:
                self.pc = self.osr & self.addr_mask
                return
            elif dest == OUT_ISR:
                self.isr = self.osr
            elif dest == OUT_NULL:
                for _ in range(min(count, 16)):
                    self._shift_out_bit()
            elif dest == OUT_PINSALL:
                self.pins_out = self.osr & 0xFF
                self.osr = (self.osr >> 8) & 0xFFFF
            self.pc = (self.pc + 1) & self.addr_mask
            return

        if op == OP_MOV:
            dest = (word >> 9) & 7
            src = (word >> 6) & 7
            mop = (word >> 4) & 3
            status = self.wait_expired
            val = self._read_reg(src, pins_in, status)
            if mop == MOV_NOT:
                val = (~val) & 0xFFFF
            elif mop == MOV_REV:
                val = bitrev8(val & 0xFF)
            elif mop == MOV_INC:
                val = (val + 1) & 0xFFFF
            self._write_reg(dest, val)
            self.pc = (self.pc + 1) & self.addr_mask
            return

        if op == OP_SET:
            dest = (word >> 9) & 7
            imm = word & 0x1FF
            if dest == SET_PINS:
                self.pins_out = imm & 0xFF
            elif dest == SET_X:
                self.x = imm & 0xFF
            elif dest == SET_Y:
                self.y = imm & 0xFF
            elif dest == SET_PINDIRS:
                self.pindirs = imm & 0xFF
            elif dest == SET_CLKDIV:
                self.clkdiv = imm & 0xFF
            elif dest == SET_OUTBASE:
                self.out_base = imm & 7
            elif dest == SET_INBASE:
                self.in_base = imm & 7
            elif dest == SET_JMPPIN:
                self.jmp_pin = imm & 7
            self.pc = (self.pc + 1) & self.addr_mask
            return

        if op == OP_DELAY:
            imm = word & 0xFFF
            if imm != 0:
                self.delay_reg = imm
            self.pc = (self.pc + 1) & self.addr_mask
            return

        if op == OP_FIFO:
            pull = (word >> 11) & 1
            iff = (word >> 10) & 1
            if pull:
                if tx_valid:
                    self.osr = tx_data & 0xFF
                    self.osr_count = 8
                    self.tx_ready_pulse = 1
                    self.pc = (self.pc + 1) & self.addr_mask
                elif iff:
                    self.pc = (self.pc + 1) & self.addr_mask
                else:
                    self.stalled = True
            else:
                if rx_ready:
                    self.rx_data = self.isr & 0xFF
                    self.rx_valid_pulse = 1
                    self.isr = 0
                    self.isr_count = 0
                    self.pc = (self.pc + 1) & self.addr_mask
                elif iff:
                    self.pc = (self.pc + 1) & self.addr_mask
                else:
                    self.stalled = True
            return

        if op == OP_CRC:
            cmd = (word >> 10) & 3
            poly_sel = (word >> 8) & 3
            imm = word & 0xFF
            width, poly = self._poly_width(poly_sel)
            if cmd == CRC_INIT:
                self.crc = imm if width <= 8 else (0xFFFF if imm == 0 else imm)
                self.crc_poly_sel = poly_sel
            elif cmd == CRC_OSR:
                self.crc = _crc_update_msb(self.crc, width, poly, self.osr & 0xFF, 8)
            elif cmd == CRC_PINS:
                self.crc = _crc_update_msb(self.crc, width, poly, pins_in & 0xFF, 8)
            elif cmd == CRC_TO_XY:
                self.x = self.crc & 0xFF
                self.y = (self.crc >> 8) & 0xFF
            self.pc = (self.pc + 1) & self.addr_mask
            return

        if op == OP_IRQ:
            wait = (word >> 11) & 1
            clear = (word >> 10) & 1
            index = (word >> 8) & 3
            bit = 1 << index
            if wait:
                level = (irq >> index) & 1
                if level:
                    if clear:
                        self.irq_out_clr = bit
                    self.pc = (self.pc + 1) & self.addr_mask
                else:
                    self.stalled = True
            else:
                if clear:
                    self.irq_out_clr = bit
                else:
                    self.irq_out_set = bit
                self.pc = (self.pc + 1) & self.addr_mask
            return

        if op == OP_CAP:
            start = (word >> 11) & 1
            self.cap_edge = (word >> 10) & 1
            self.cap_trig = (word >> 8) & 3
            self.cap_period = word & 0xFF
            self.cap_cmd = 1 if start else 2
            self.pc = (self.pc + 1) & self.addr_mask
            return

        if op == OP_PLAY:
            start = (word >> 11) & 1
            self.play_period = word & 0x7FF
            self.play_cmd = 1 if start else 2
            self.pc = (self.pc + 1) & self.addr_mask
            return

        if op == OP_MODE:
            self.osr_right = (word >> 11) & 1
            self.isr_left = (word >> 10) & 1
            self.autopush = (word >> 9) & 1
            self.autopull = (word >> 8) & 1
            self.thresh = (word >> 3) & 0x1F
            self.pc = (self.pc + 1) & self.addr_mask
            return

        if op == OP_NRZI:
            self.nrzi_en = (word >> 11) & 1
            self.stuff_en = (word >> 10) & 1
            self.ones_run = 0
            self.pc = (self.pc + 1) & self.addr_mask
            return

        if op == OP_PIN:
            index = (word >> 8) & 7
            value = (word >> 7) & 1
            oe = (word >> 6) & 1
            mask = 1 << index
            if oe:
                self.pindirs |= mask
            else:
                self.pindirs &= ~mask
            if value:
                self.pins_out |= mask
            else:
                self.pins_out &= ~mask
            self.pc = (self.pc + 1) & self.addr_mask
            return

        if op == OP_HALT:
            self.halted = True
            return

        self.pc = (self.pc + 1) & self.addr_mask
