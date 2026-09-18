# Copyright (c) 2026 Narasinga Ujjini
# SPDX-License-Identifier: Apache-2.0
"""Protocol firmware in Cycle assembly.

Pin map used by these programs (uio[7:0]):
  UART: TX = uio[0], RX = uio[1]
  SPI : SCLK = uio[0], MOSI = uio[1], MISO = uio[2], CS = uio[3]
  I2C : SCL = uio[0], SDA = uio[1]   (open-drain: oe=1 drives 0, oe=0 releases)
  JTAG: TCK = uio[0], TMS = uio[1], TDI = uio[2], TDO = uio[3]
  SWD : SWCLK = uio[0], SWDIO = uio[1]
"""

from isa.asm import Assembler
from isa.encoding import (
    IN_PINS,
    JC_ALWAYS,
    JC_XDEC,
    JC_XEQ0,
    JC_YDEC,
    OUT_PINS,
    OUT_X,
    SET_CLKDIV,
    SET_INBASE,
    SET_JMPPIN,
    SET_OUTBASE,
    SET_PINS,
    SET_PINDIRS,
    SET_X,
    SET_Y,
    WS_PIN,
)


def uart_tx(baud_div=15) -> list[int]:
    """8N1 TX on uio[0]. PULL a byte, shift LSB first, idle high.

    Each bit is  (baud_div+1) ticks plus the OUT/SET instruction.
    Callers should set SM clkdiv so that one tick is one bit-time, or
    pass baud_div as extra DELAY after each bit. Here clkdiv is set to
    baud_div and DELAY is 0, so one instruction per bit-time after SET CLKDIV.
    """
    a = Assembler()
    a.set(SET_OUTBASE, 0)
    a.set(SET_PINDIRS, 0x01)
    a.set(SET_PINS, 0x01)  # idle high
    a.set(SET_CLKDIV, baud_div)
    a.label("idle")
    a.pin(0, 1, 1)
    a.pull(iff=0)
    a.set(SET_X, 7)  # 8 data bits, x-- loop
    a.pin(0, 0, 1)  # start bit (one tick)
    a.label("bits")
    a.out(1, OUT_PINS)
    a.jmp(JC_XDEC, label="bits")
    a.pin(0, 1, 1)  # stop bit
    a.jmp_always(label="idle")
    return a.words()


def uart_rx(baud_div=15) -> list[int]:
    """8N1 RX on uio[1]. Wait falling start, sample mid-bit, PUSH byte."""
    a = Assembler()
    a.set(SET_INBASE, 1)
    a.set(SET_JMPPIN, 1)
    a.set(SET_PINDIRS, 0x00)
    a.set(SET_CLKDIV, baud_div)
    a.label("wait_idle")
    a.wait(1, WS_PIN, 1, timeout_exp=0)  # wait RX high
    a.label("wait_start")
    a.wait(0, WS_PIN, 1, timeout_exp=0)  # falling edge
    a.set(SET_X, 7)
    # half-bit delay to sample center: DELAY of clkdiv already is 1 bit,
    # so we use a shorter extra wait via DELAY 0 after SET? At clkdiv=baud,
    # one tick = one bit. Wait 0 extra then sample after 1 tick ~ end of start.
    # Better: sample after 1 tick (middle-ish if we started at the edge).
    a.delay(0)
    a.label("rbits")
    a.inn(1, IN_PINS)
    a.jmp(JC_XDEC, label="rbits")
    a.push(iff=0)
    a.jmp_always(label="wait_idle")
    return a.words()


def spi_master_mode0(clkdiv=0) -> list[int]:
    """SPI mode 0 master: CS uio[3], SCLK[0], MOSI[1], MISO[2]. 8 bits per PULL/PUSH."""
    a = Assembler()
    a.set(SET_CLKDIV, clkdiv)
    a.set(SET_PINDIRS, 0x0B)  # 0,1,3 outputs; 2 input
    a.pin(3, 1, 1)  # CS high
    a.pin(0, 0, 1)  # SCLK low
    a.label("idle")
    a.pull(iff=0)
    a.pin(3, 0, 1)  # CS low
    a.set(SET_X, 7)
    a.label("bit")
    # MOSI from OSR onto pin 1
    a.set(SET_OUTBASE, 1)
    a.out(1, OUT_PINS)
    a.pin(0, 1, 1)  # SCLK high: sample MISO
    a.set(SET_INBASE, 2)
    a.inn(1, IN_PINS)
    a.pin(0, 0, 1)  # SCLK low
    a.jmp(JC_XDEC, label="bit")
    a.pin(3, 1, 1)
    a.push(iff=0)
    a.jmp_always(label="idle")
    return a.words()


def spi_slave_mode0() -> list[int]:
    """SPI mode 0 slave. Wait CS low, for each clock sample MOSI, drive MISO from PULL."""
    a = Assembler()
    a.set(SET_PINDIRS, 0x04)  # MISO output only
    a.set(SET_OUTBASE, 2)
    a.set(SET_INBASE, 1)
    a.label("wait_cs")
    a.wait(0, WS_PIN, 3)  # CS low
    a.pull(iff=1)  # load response if host gave one
    a.set(SET_X, 7)
    a.label("sbit")
    a.wait(1, WS_PIN, 0)  # clock high
    a.inn(1, IN_PINS)
    a.out(1, OUT_PINS)
    a.wait(0, WS_PIN, 0)
    a.jmp(JC_XDEC, label="sbit")
    a.push(iff=0)
    a.jmp_always(label="wait_cs")
    return a.words()


def i2c_master_write(clkdiv=3) -> list[int]:
    """I2C master write: PULL address+w, PULL data byte, open-drain SCL/SDA.

    Open-drain: PIN index,value,oe — value is 0 when driving, oe=0 releases.
    We only ever drive 0. SCL=uio[0], SDA=uio[1].
    """
    a = Assembler()
    a.set(SET_CLKDIV, clkdiv)
    a.set(SET_PINDIRS, 0x00)  # released
    a.set(SET_PINS, 0x00)
    a.label("idle")
    a.pull(iff=0)  # address byte in OSR (7-bit addr << 1 | w=0)
    # START: SDA high->low while SCL high. Both released = high via pull-ups.
    a.pin(1, 0, 1)  # SDA drive 0
    a.delay(1)
    a.pin(0, 0, 1)  # SCL drive 0
    a.set(SET_Y, 7)
    a.label("abyte")
    a.set(SET_OUTBASE, 1)
    a.out(1, OUT_X)  # x = data bit, OSR shifts; Y is the loop counter
    a.jmp(JC_XEQ0, label="sda0")
    a.pin(1, 0, 0)  # release SDA (one)
    a.jmp_always(label="sclh")
    a.label("sda0")
    a.pin(1, 0, 1)  # drive 0
    a.label("sclh")
    a.pin(0, 0, 0)  # release SCL (high)
    a.delay(0)
    a.pin(0, 0, 1)  # SCL low
    a.jmp(JC_YDEC, label="abyte")
    # ACK: release SDA, pulse SCL, sample
    a.pin(1, 0, 0)
    a.pin(0, 0, 0)
    a.set(SET_INBASE, 1)
    a.inn(1, IN_PINS)
    a.pin(0, 0, 1)
    # data byte
    a.pull(iff=0)
    a.set(SET_Y, 7)
    a.label("dbyte")
    a.out(1, OUT_X)
    a.jmp(JC_XEQ0, label="dsda0")
    a.pin(1, 0, 0)
    a.jmp_always(label="dsclh")
    a.label("dsda0")
    a.pin(1, 0, 1)
    a.label("dsclh")
    a.pin(0, 0, 0)
    a.delay(0)
    a.pin(0, 0, 1)
    a.jmp(JC_YDEC, label="dbyte")
    a.pin(1, 0, 0)
    a.pin(0, 0, 0)
    a.inn(1, IN_PINS)
    a.pin(0, 0, 1)
    # STOP: SDA low, SCL high, SDA high (release)
    a.pin(1, 0, 1)
    a.pin(0, 0, 0)
    a.delay(0)
    a.pin(1, 0, 0)
    a.push(iff=1)
    a.jmp_always(label="idle")
    return a.words()


def i2c_slave_listen() -> list[int]:
    """I2C slave: wait START, shift 8 bits, ACK by driving SDA, PUSH address."""
    a = Assembler()
    a.set(SET_PINDIRS, 0x00)
    a.set(SET_INBASE, 1)
    a.label("idle")
    a.wait(1, WS_PIN, 0)  # SCL high
    a.wait(0, WS_PIN, 1)  # SDA falls while SCL high = START
    a.set(SET_X, 7)
    a.label("sbit")
    a.wait(0, WS_PIN, 0)
    a.wait(1, WS_PIN, 0)  # rising SCL: sample SDA
    a.inn(1, IN_PINS)
    a.jmp(JC_XDEC, label="sbit")
    # ACK
    a.wait(0, WS_PIN, 0)
    a.pin(1, 0, 1)
    a.wait(1, WS_PIN, 0)
    a.wait(0, WS_PIN, 0)
    a.pin(1, 0, 0)
    a.push(iff=0)
    a.jmp_always(label="idle")
    return a.words()


def jtag_shift() -> list[int]:
    """Shift one byte TMS=0: PULL TDI byte, PUSH TDO byte. TCK pulse per bit."""
    a = Assembler()
    a.set(SET_PINDIRS, 0x07)  # TCK TMS TDI out, TDO in
    a.set(SET_OUTBASE, 2)  # TDI
    a.set(SET_INBASE, 3)
    a.pin(1, 0, 1)  # TMS 0
    a.pin(0, 0, 1)  # TCK 0
    a.label("idle")
    a.pull(iff=0)
    a.set(SET_X, 7)
    a.label("bit")
    a.out(1, OUT_PINS)  # TDI
    a.pin(0, 1, 1)
    a.inn(1, IN_PINS)  # TDO
    a.pin(0, 0, 1)
    a.jmp(JC_XDEC, label="bit")
    a.push(iff=0)
    a.jmp_always(label="idle")
    return a.words()


def swd_write_bits() -> list[int]:
    """SWD: PULL byte, clock it out on SWDIO LSB first."""
    a = Assembler()
    a.set(SET_PINDIRS, 0x03)
    a.set(SET_OUTBASE, 1)
    a.pin(0, 0, 1)
    a.label("idle")
    a.pull(iff=0)
    a.set(SET_X, 7)
    a.label("bit")
    a.out(1, OUT_PINS)
    a.pin(0, 1, 1)
    a.delay(0)
    a.pin(0, 0, 1)
    a.jmp(JC_XDEC, label="bit")
    a.jmp_always(label="idle")
    return a.words()


def capture_loop(period=0) -> list[int]:
    """Start capture then halt — host dumps the buffer."""
    a = Assembler()
    a.cap(1, edge=0, trig_pin=0, period=period)
    a.halt()
    return a.words()


def usb_ls_idle_k(clkdiv=31) -> list[int]:
    """Low-speed USB: NRZI J/K idle pattern on D-/D+ as uio[0]/uio[1].

    LS idle is J: D- high, D+ low. K is the opposite. This program
    emits a K then J at 1.5 Mbit/s when sysclk=48 MHz and clkdiv=31
    (32 clocks/bit). Stretch goal firmware — PHY resistors on the board.
    """
    a = Assembler()
    a.set(SET_CLKDIV, clkdiv)
    a.set(SET_PINDIRS, 0x03)
    a.nrzi(0, 0)
    a.label("loop")
    a.set(SET_PINS, 0x01)  # J for LS: D- =1 D+=0 if uio0=D- uio1=D+
    a.delay(0)
    a.set(SET_PINS, 0x02)  # K
    a.delay(0)
    a.jmp_always(label="loop")
    return a.words()


PROGRAMS = {
    "uart_tx": uart_tx,
    "uart_rx": uart_rx,
    "spi_master": spi_master_mode0,
    "spi_slave": spi_slave_mode0,
    "i2c_master": i2c_master_write,
    "i2c_slave": i2c_slave_listen,
    "jtag": jtag_shift,
    "swd": swd_write_bits,
    "capture": capture_loop,
    "usb_ls": usb_ls_idle_k,
}


if __name__ == "__main__":
    import pathlib

    out = pathlib.Path(__file__).resolve().parent
    for name, fn in PROGRAMS.items():
        words = fn()
        (out / f"{name}.hex").write_text("\n".join(f"{w:04x}" for w in words) + "\n")
        print(f"{name:12} {len(words):3} words")
