# Cycle — protocol emulator ASIC

Open-source entry for [Jane Street’s protocol emulator ASIC competition](https://blog.janestreet.com/protocol-emulator-asic-competition/).

**Chip name:** `tt_um_NarasingaUjjini_cycle`
**Process:** IHP 130 nm CMOS5L via Tiny Tapeout (6×4 tiles, ~0.7 mm²)
**Repo:** [github.com/NarasingaUjjini/JaneStreetASIC](https://github.com/NarasingaUjjini/JaneStreetASIC)

This is a tiny **programmable pin machine**, not a UART/SPI/I2C block glued together. After the chip is manufactured you load new firmware over a host UART and it can speak protocols that did not exist when the silicon was taped out. The extra that is not a PIO clone: **cycle-accurate capture and replay** of the eight protocol pins, which is what you actually want when reverse-engineering a bus.

If you have never designed a chip, read [docs/beginner.md](docs/beginner.md) first. The instruction set is frozen in [isa/SPEC.md](isa/SPEC.md). The Python file [isa/golden.py](isa/golden.py) is the spec: if Verilog disagrees, Verilog is wrong.

## What you can do with it

- Implement **UART, SPI, I2C** in firmware (shipped under `fw/`)
- **JTAG** and **SWD** for talking to other chips
- **Sniff** an unknown bus into a 64-sample buffer and dump it over UART
- **Replay** a captured trace, or mutate it from the host
- Stretch: **low-speed USB** NRZI helper + idle K/J firmware (`fw/programs.py`)

Two state machines share 128 × 16-bit instruction memory (flop RAM, fits 6×4). An IHP **512×16 SRAM** wrapper is ready in `src/cycle_sram_ihp.v` for the CMOS5L harden if the macro is enabled.

## How to run locally (free tools)

```bash
sudo apt-get install -y iverilog yosys python3-pip
pip install -r test/requirements.txt
export PYTHONPATH=$PWD
python3 -m pytest isa/test_golden.py -q
python3 fw/programs.py          # writes fw/*.hex
cd test && make                 # RTL sim via cocotb + Icarus
../scripts/synth.sh             # Yosys cell count
```

Host UART in simulation uses 8 clocks per bit so tests are fast. On the Tiny Tapeout board, set the project clock to **48 MHz**. USB low-speed is then 32 clocks per bit (`clkdiv=31`).

## Host protocol

8N1 on `ui[0]` (RX) and `uo[0]` (TX). Every command starts with `0xA5`.

| Bytes after magic | Meaning |
| --- | --- |
| `01 addr lo hi` | Write one instruction word (little-endian) |
| `02` | RUN SM0 |
| `03` | HALT |
| `04 data` | Push a byte into SM0 TX FIFO |
| `05` | Pop SM0 RX FIFO, chip replies with the byte |
| `06` | Status byte reply |
| `07 sm pc` | Set PC |
| `09` / `0A` / `0B` | Capture on / off / read one sample |
| `0C` | Replay capture |
| `0E` | RUN SM1 |

Protocol GPIOs are `uio[7:0]`. Firmware pin maps are documented in `fw/programs.py`.

## Verification

Jane Street asked for this. We treat RTL as untrusted (including RTL written with AI):

1. Golden Python model of every opcode (`isa/golden.py`)
2. Directed cocotb tests for UART, SPI, I2C open-drain, JTAG, capture
3. Constrained-random programs vs the golden model (`isa/test_random.py`)
4. Formal pin-safety properties (`formal/`)
5. Yosys synthesis stats committed under `docs/area.md`
6. Gate-level / Tiny Tapeout GL job once GDS runs on GitHub Actions

See [docs/verification.md](docs/verification.md).

## Contest notes

- Deadline 18 January 2027. Prize: Jane Street pays to tape out novel designs on the March 2027 CMOS5L shuttle.
- Tile size is **6×4** as specified. If they unlock 8×4, the unused area takes a 512×16 SRAM + a third capture bank.
- GDS GitHub Action currently uses the public IHP flow (`ttihp26b`). Switch the PDK to `ihp-sg13cmos5l` when Jane Street’s CMOS5L template arrives.

License: Apache-2.0 (Tiny Tapeout template).
