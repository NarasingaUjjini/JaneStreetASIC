# Cycle: a protocol VM with capture/replay

Jane Street asked for a general-purpose protocol emulator, not UART+SPI+I2C IP. Cycle is a 16-bit ISA whose only job is pins and time, plus the reverse-engineering feature their hardware team actually uses: **record a bus, dump it, play it back**.

## Why not PIO

RP2040 PIO is the right *shape* (tiny state machines, delay, shift). It is the wrong *product* for this contest:

- 32 instructions, shared, no capture buffer
- No CRC/NRZI, so USB-LS and CAN are painful
- No open-drain story in the ISA (you fake it)
- No golden model you can prove firmware against

Cycle keeps the PIO-like tick model, then adds CAP/PLAY, CRC-8/16, NRZI+bit-stuff, dual fetch from 128×16 (or 512×16 SRAM), and a Python spec that RTL must match.

## Verification as the pitch

The RTL was written with an AI agent. The contest text calls out AI-assisted verification. So the methodology is: **the generator is untrusted**.

The spec is `isa/golden.py`. Directed tests cover UART 0x55, SPI CS/SCLK, I2C open-drain START, JTAG TCK, capture. Random legal programs must keep PC in range. Yosys cell counts are in `docs/area.md`. Tiny Tapeout GDS/GL is the factory check.

An early AI bug used X as both I2C bit and loop counter; Y is the counter now. That class of bug is why the golden model exists.

## What we would do on silicon

48 MHz from the TT board. Host UART from the RP2040. Pull-ups on I2C. Firmware in `fw/*.hex`. New protocols after tapeout are new hex files, not a new shuttle.
