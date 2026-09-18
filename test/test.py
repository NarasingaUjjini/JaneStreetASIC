# SPDX-License-Identifier: Apache-2.0
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

from fw.programs import (
    capture_loop,
    i2c_master_write,
    jtag_shift,
    spi_master_mode0,
    uart_tx,
)
from host import load_program, reset, run_sms, stat, wfifo


@cocotb.test()
async def test_reset_and_status(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    s = await stat(dut)
    # bit0 always 1, bit1 running=0 after reset
    assert s & 1 == 1
    assert (s >> 1) & 1 == 0


@cocotb.test()
async def test_uart_tx_byte(dut):
    """Load UART TX firmware, send 0x55, check start/data/stop on uio[0]."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    words = uart_tx(baud_div=0)
    await load_program(dut, words)
    await run_sms(dut)
    await wfifo(dut, 0x55)

    # Idle high, wait for start bit (driven low).
    saw_start = False
    for _ in range(400):
        await RisingEdge(dut.clk)
        driven = int(dut.uio_oe.value) & 1
        val = int(dut.uio_out.value) & 1
        if driven and val == 0:
            saw_start = True
            break
    assert saw_start, "UART start bit never appeared"

    bits = []
    for _ in range(8):
        await RisingEdge(dut.clk)  # OUT
        bits.append(int(dut.uio_out.value) & 1)
        await RisingEdge(dut.clk)  # JMP XDEC
    value = 0
    for i, b in enumerate(bits):
        value |= b << i
    assert value == 0x55, f"got {value:#x} bits={bits}"


@cocotb.test()
async def test_spi_master_cs_and_clock(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await load_program(dut, spi_master_mode0(clkdiv=0))
    await run_sms(dut)
    await wfifo(dut, 0xA5)

    saw_cs_low = False
    saw_sclk = False
    last_sclk = 0
    for _ in range(800):
        await RisingEdge(dut.clk)
        oe = int(dut.uio_oe.value)
        out = int(dut.uio_out.value)
        cs = 1 if not (oe & 8) else (out >> 3) & 1
        sclk = 1 if not (oe & 1) else (out >> 0) & 1
        if cs == 0:
            saw_cs_low = True
        if saw_cs_low and sclk == 1 and last_sclk == 0:
            saw_sclk = True
            break
        last_sclk = sclk
    assert saw_cs_low, "SPI CS never went low"
    assert saw_sclk, "SPI SCLK never rose"


@cocotb.test()
async def test_i2c_start_open_drain(dut):
    """I2C master must only drive 0 (open-drain). START pulls SDA then SCL."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    # External pull-ups: when oe=0, treat pin as 1.
    dut.uio_in.value = 0x03
    await load_program(dut, i2c_master_write(clkdiv=0))
    await run_sms(dut)
    await wfifo(dut, 0xA0)  # address
    await wfifo(dut, 0x12)  # data

    saw_sda_low = False
    illegal_drive_high = False
    for _ in range(600):
        await RisingEdge(dut.clk)
        oe = int(dut.uio_oe.value)
        outv = int(dut.uio_out.value)
        # If driving, the merged pin value must be 0 (open-drain).
        for bit in (0, 1):
            if (oe >> bit) & 1:
                if (outv >> bit) & 1:
                    illegal_drive_high = True
                else:
                    if bit == 1:
                        saw_sda_low = True
        # Feed back driven-low / pulled-up-high into uio_in
        sda = 0 if (oe & 2) and not (outv & 2) else 1
        scl = 0 if (oe & 1) and not (outv & 1) else 1
        dut.uio_in.value = scl | (sda << 1)
    assert not illegal_drive_high, "I2C drove a 1 — that is not open-drain"
    assert saw_sda_low, "I2C never pulled SDA low for START"


@cocotb.test()
async def test_capture_starts(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.uio_in.value = 0xA5
    await load_program(dut, capture_loop(period=0))
    await run_sms(dut)
    saw = False
    for _ in range(200):
        await RisingEdge(dut.clk)
        if (int(dut.uo_out.value) >> 6) & 1:
            saw = True
            break
    assert saw, "capture active flag never rose"


@cocotb.test()
async def test_jtag_tck_toggles(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await load_program(dut, jtag_shift())
    await run_sms(dut)
    await wfifo(dut, 0x09)
    toggles = 0
    last = 0
    for _ in range(400):
        await RisingEdge(dut.clk)
        tck = (int(dut.uio_out.value) >> 0) & 1
        if tck and not last:
            toggles += 1
        last = tck
    assert toggles >= 4, f"JTAG TCK only rose {toggles} times"
