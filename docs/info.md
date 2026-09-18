<!---
Tiny Tapeout datasheet for Cycle, Jane Street protocol-emulator ASIC.
-->

## How it works

The repository README is the human explanation (what the contest is, what a pin is, and a UART walkthrough). This page is the Tiny Tapeout datasheet.

Cycle is a dual state-machine protocol emulator. Each machine has a 16-bit ISA specialised for waiting on pins, driving pins, shifting bits, and counting clocks. Instruction memory is 128 × 16-bit dual-read flop RAM (an IHP 512×16 SRAM wrapper is included for the CMOS5L harden).

After reset the chip is halted and listens on a host UART (`ui[0]` RX, `uo[0]` TX, 8 clocks per bit in the default RTL parameter; scale `BAUD_DIV` for 115200 at your board clock). Load firmware with `A5 01 addr lo hi`, then `A5 02` to RUN.

Unique function: a 64-sample capture buffer can record `uio[7:0]` every N clocks and play the trace back. That is the reverse-engineering feature — sniff a bus, dump it, replay it.

Pin merge is wired-AND: a 0 from either state machine wins. I2C firmware only ever drives 0 (open-drain).

## How to test

1. Clock the design at 48 MHz on the Tiny Tapeout board (or any rate in RTL sim).
2. Idle `ui[0]` high. Send `A5 06` — you should get a status byte back on `uo[0]`.
3. Load `fw/uart_tx.hex` one word at a time, RUN, then `A5 04 55`. `uio[0]` should emit 8N1 `0x55`.
4. For I2C, put pull-ups on `uio[0]` (SCL) and `uio[1]` (SDA). Load `fw/i2c_master.hex`.
5. Capture: load `fw/capture.hex`, RUN, watch `uo[6]`, then `A5 0B` to read samples.

See the repository README for the full command table and ISA spec.

## External hardware

- Host UART at 3.3 V (the Tiny Tapeout RP2040 can bit-bang this)
- I2C: 2× 4.7 kΩ pull-ups to 3.3 V on SCL/SDA
- USB-LS stretch: 1.5 kΩ pull-up on D−, series 33–68 Ω on D+/D−
- SPI/JTAG/SWD: jumper wires to the target
