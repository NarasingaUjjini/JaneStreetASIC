# SPDX-License-Identifier: Apache-2.0
"""Host UART helpers for Cycle (BAUD_DIV=8)."""

from cocotb.triggers import ClockCycles, RisingEdge


BAUD = 8


async def reset(dut, cycles=8):
    dut.ena.value = 1
    dut.ui_in.value = 1  # UART RX idle high
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, cycles)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 4)


async def send_byte(dut, value: int, clocks_per_bit: int = BAUD):
    dut.ui_in.value = 0  # start
    await ClockCycles(dut.clk, clocks_per_bit)
    for i in range(8):
        dut.ui_in.value = (value >> i) & 1
        await ClockCycles(dut.clk, clocks_per_bit)
    dut.ui_in.value = 1  # stop
    await ClockCycles(dut.clk, clocks_per_bit)


async def recv_byte(dut, clocks_per_bit: int = BAUD, timeout=2000) -> int:
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if int(dut.uo_out.value) & 1 == 0:
            break
    else:
        raise TimeoutError("no UART start bit on uo[0]")
    await ClockCycles(dut.clk, clocks_per_bit + clocks_per_bit // 2)
    bits = 0
    for i in range(8):
        bits |= (int(dut.uo_out.value) & 1) << i
        await ClockCycles(dut.clk, clocks_per_bit)
    await ClockCycles(dut.clk, clocks_per_bit)
    return bits


async def cmd(dut, *payload: int):
    await send_byte(dut, 0xA5)
    for b in payload:
        await send_byte(dut, b)


async def wmem(dut, addr: int, word: int):
    await cmd(dut, 0x01, addr & 0x7F, word & 0xFF, (word >> 8) & 0xFF)


async def load_program(dut, words):
    for i, w in enumerate(words):
        await wmem(dut, i, w)


async def run_sms(dut):
    await cmd(dut, 0x02)


async def halt_sms(dut):
    await cmd(dut, 0x03)


async def wfifo(dut, data: int):
    await cmd(dut, 0x04, data & 0xFF)


async def stat(dut) -> int:
    await cmd(dut, 0x06)
    return await recv_byte(dut)
