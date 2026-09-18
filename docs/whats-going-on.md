# What’s going on

**Read this first** if you have never designed a chip. The rest of the repo is the actual contest entry. This page is the tour.

A one-line glossary of every bold term lives in [beginner.md](beginner.md).

---

## 1. The contest, in plain English

[Jane Street](https://blog.janestreet.com/protocol-emulator-asic-competition/) will **pay to manufacture** a handful of student/hobby chips on a Tiny Tapeout shuttle (IHP 130 nm **CMOS5L**, March 2027 target). Deadline to submit: **18 January 2027**.

They do **not** want a chip that is “a UART block + an SPI block + an I2C block glued together.” Those protocols are examples. The point is a **reprogrammable pin machine**: after the silicon is frozen, you load new firmware and it can speak a bus that did not exist when the chip was taped out.

They also said verification matters — especially if AI wrote the RTL. Unique function plus a story for why the circuit is trustworthy beats a flashy demo that only works in one test.

Winning means: they pick the design, pay for the shuttle, and you get a real chip on a board months later. There is no live scoreboard.

You already signed up. This GitHub repo **is** the entry. The final Jane Street form comes later; until then, building in public is allowed and encouraged.

---

## 2. What Cycle actually is

Imagine a music box.

- The **metal comb** is the hardware: a tiny instruction set whose only job is *wait on a pin, drive a pin, shift a bit, wait N clocks*. That is etched in silicon and cannot change.
- The **paper roll** is firmware: a list of 16-bit instructions in on-chip RAM. After you have the physical chip, you load a new roll over a serial link. New protocol, same silicon.
- **Capture/replay** is the extra that is not a copy of Raspberry Pi PIO: record what the eight protocol pins did, dump the trace, play it back. That is the reverse-engineering tool Jane Street’s hardware team actually uses.

Cycle is **not**:

- a CPU that runs C or RISC-V
- a USB/SPI/I2C peripheral you instantiate from a catalog
- an FPGA you keep rewriting

It is two small state machines sharing 128 instructions, plus a 64-sample sniffer, plus a host UART so a laptop (or the Tiny Tapeout RP2040) can load programs.

Name on silicon: `tt_um_NarasingaUjjini_cycle`. Area: **6×4 Tiny Tapeout tiles** (~0.7 mm²), which Jane Street fixed in the rules.

---

## 3. The path from this folder to a real chip

```
idea  →  instruction set (isa/)  →  Verilog circuit (src/)
      →  tests that treat the Verilog as guilty (test/, isa/test_*)
      →  GitHub Action draws the layout (GDS)
      →  Jane Street picks winners  →  foundry etches wafers  →  board in the mail
```

| Stage | What it means | Where it lives |
| --- | --- | --- |
| Spec | What each 16-bit opcode *must* do | [isa/SPEC.md](../isa/SPEC.md), [isa/golden.py](../isa/golden.py) |
| RTL | The circuit, in Verilog | `src/*.v` |
| Firmware | Example “paper rolls” (UART, SPI, I2C, JTAG, …) | `fw/programs.py` → `fw/*.hex` |
| Simulation | Pretend board: clock, reset, pins | `test/` (cocotb + Icarus) |
| Synthesis | Count gates; did it fit? | `scripts/synth.sh`, [area.md](area.md) |
| GDS | Factory file. Tiny Tapeout builds this on GitHub | `.github/workflows/gds.yaml` |
| Datasheet | What Tiny Tapeout prints on the project page | [info.md](info.md) |

You do **not** need a cleanroom. The expensive part (masks, wafers) is what Jane Street pays for if they select the design. Local work uses free tools: Icarus Verilog, Yosys, Python.

The GitHub badges at the top of the README are the live status of those factory jobs. Green `test` means the simulator still agrees. Green `gds` means LibreLane produced a layout for the CMOS5L process. The first GDS run takes a long time (PDK + place-and-route); that is normal.

---

## 4. Picture of the chip

Tiny Tapeout gives every project the same cage of wires. We cannot add pins.

```
Laptop / RP2040
        │  serial (UART)
        ▼
   ui[0]  HOST_RX  ──► host UART RX ──► command FSM ──► write instruction RAM
   uo[0]  HOST_TX  ◄── host UART TX ◄─┘                    │
                                                           ├─► SM0 ──┐
                                                           └─► SM1 ──┤
                                                                     ▼
                                                              0 wins (wired-AND)
                                                                     ▼
                                                              uio[7:0]  ◄── other chips
                                                                     ▲
   Capture 64×8 samples the same eight pins, or drives them (PLAY)
```

- **`ui[7:0]`** — dedicated inputs. We use `ui[0]` as host RX and `ui[1]` as a trigger. The rest are unused.
- **`uo[7:0]`** — dedicated outputs. Host TX, “running,” FIFO flags, halt flags, capture flags.
- **`uio[7:0]`** — eight bidirectional **protocol** pins. Firmware decides which of these is UART TX, SPI clock, I2C SDA, etc.
- **`clk` / `rst_n` / `ena`** — board clock, active-low reset, “this tile is powered.”

Why “0 wins”: I2C requires **open-drain** (drive low, or let a resistor pull the wire high). If two state machines share a pin, a 0 from either one pulls the net down. Firmware that needs open-drain never drives a 1; it only drives 0 or releases the pin.

Two state machines exist so you can, for example, speak SPI on some pins while the other machine sniffs, or run a clock on SM0 and data on SM1. Command `0x02` starts **SM0 only**. Command `0x0E` starts SM1. That is deliberate: if both run the same program they fight over the pins (wired-AND holds clocks low). Unused memory boots as HALT.

---

## 5. Map of this repository

```
README.md                 ← badges + short pitch; start here points at this file
info.yaml                 ← Tiny Tapeout project card (title, 6x4 tiles, pin names)
src/
  tt_um_NarasingaUjjini_cycle.v   top of the chip (must keep this pin list)
  cycle_sm.v              one programmable state machine (instantiated twice)
  cycle_mem.v             128 × 16-bit dual-read instruction RAM
  cycle_host.v            parses 0xA5 commands from the host UART
  cycle_uart_rx.v / _tx.v host serial
  cycle_fifo.v            bytes in/out of SM0
  cycle_capture.v         64-sample sniffer / player
  cycle_isa.vh            opcode numbers (must match Python)
  cycle_sram_ihp.v        unused on 6×4; SRAM wrapper if 8×4 unlocks
  config.json             LibreLane knobs (clock period, density, PDN)
isa/
  SPEC.md                 frozen 16-bit encoding
  golden.py               the law — Verilog is wrong if they disagree
  encoding.py / asm.py    assembler used by firmware
fw/programs.py            UART/SPI/I2C/JTAG/SWD/USB-LS/capture programs
test/                     cocotb tests that load firmware and watch pins
formal/                   pin-safety properties
docs/                     you are here
.github/workflows/        CMOS5L GDS, docs, tests (official Tiny Tapeout actions)
```

The Verilog template this is based on: [TinyTapeout/ttihp-verilog-template@cmos5l](https://github.com/TinyTapeout/ttihp-verilog-template/tree/cmos5l). Jane Street told entrants to start there and set `tiles: "6x4"` in `info.yaml`. We did.

---

## 6. Walkthrough: make pin 0 speak UART `0x55`

This is the first thing Jane Street suggested: get a UART transmitter out of a pin, then make it programmable. Here is the programmable version, end to end.

### 6.1 Firmware (the paper roll)

`fw/programs.py` function `uart_tx`:

1. Set pin 0 as an output, idle **high** (UART idle is 1).
2. **PULL** a byte from the host FIFO (stall until a byte arrives).
3. Drive pin 0 **low** for one bit-time (start bit).
4. Shift out eight data bits, least-significant first (`OUT 1, PINS` in a loop).
5. Drive pin 0 **high** (stop bit).
6. Jump back to idle.

That list is assembled into 16-bit words and written to `fw/uart_tx.hex`.

### 6.2 Host commands (how the laptop talks to the chip)

Every command starts with magic byte `0xA5` on `ui[0]`.

| You send | Chip does |
| --- | --- |
| `A5 01 addr lo hi` | Write one instruction at `addr` |
| `A5 02` | RUN SM0 |
| `A5 04 55` | Push byte `0x55` into SM0’s TX FIFO |
| `A5 06` | Reply with a status byte on `uo[0]` |

So a session is: reset → load every word of `uart_tx` → `RUN` → push `0x55` → watch `uio[0]` wiggle `0x55` in 8N1.

Simulation does exactly that in `test/test.py` (`test_uart_tx_byte`). Host UART in sim is 8 clocks per bit so tests finish in a second. On the real Tiny Tapeout board you would clock the project at **48 MHz** and raise `BAUD_DIV` for 115200 baud.

### 6.3 What “programmable” bought you

The transistors do not contain a UART. They contain WAIT/DRIVE/SHIFT/DELAY. SPI firmware in the same file uses the same opcodes to toggle a clock and a chip-select. I2C firmware only ever drives 0 (open-drain). After tapeout, a new protocol is a new hex file, not a new shuttle.

---

## 7. How we know the circuit is not lying

Jane Street called out AI-assisted verification. The RTL in this repo was written with an AI agent. So the rule is: **the generator is untrusted.**

1. **Python is the spec.** `isa/golden.py` implements every opcode. If Verilog disagrees, Verilog is wrong. Change `cycle_isa.vh`, `encoding.py`, and `golden.py` in the same commit.
2. **Directed tests** load real firmware and watch real pins: UART `0x55`, SPI CS/SCLK, I2C START never drives 1, JTAG TCK toggles, capture flag rises.
3. **Random legal programs** must not crash the golden model (PC stays in 0..127).
4. **Formal pin-safety** sketches live in `formal/` (SymbiYosys optional; Icarus can run the same asserts).
5. **Yosys cell count** is committed in [area.md](area.md) (~15k generic cells vs ~24k budget).
6. **Gate-level / GDS** on GitHub is the factory check: same tests against the CMOS5L netlist after place-and-route.

A real bug this caught: early I2C firmware used register X as both “which bit” and “loop counter,” so the loop destroyed the data. Y is the counter now. That is the class of mistake a golden model + directed test is for.

The judge-facing pitch is [writeup.md](writeup.md). The longer verification note is [verification.md](verification.md).

---

## 8. What you do next (and what you do not)

Already done:

- Contest signup
- ISA frozen
- Dual SM + host UART + capture/replay RTL
- Firmware for UART, SPI, I2C, JTAG, SWD, capture, USB-LS helper
- Tests + golden model
- Official CMOS5L template, 6×4 tiles, pushed to [github.com/NarasingaUjjini/JaneStreetASIC](https://github.com/NarasingaUjjini/JaneStreetASIC)

You should:

1. Watch the Actions tab. `test` and `docs` should stay green. `gds` is the long one; first run often takes most of an hour. If it fails, the log is the next debugging job (timing, density, DRC) — not a reason to rewrite the ISA.
2. Leave GitHub Actions and GitHub Pages enabled so Tiny Tapeout can publish the layout viewer.
3. When GDS is green, download the artifact and look at the viewer. That is the actual rectangle of silicon.
4. Do **not** submit to Jane Street yet. They said they will add a final form closer to 18 January 2027. Keep iterating (tighter tests, a clean GDS, maybe SRAM if they unlock 8×4).
5. Run locally any time:

```bash
sudo apt-get install -y iverilog yosys python3-pip
pip install -r test/requirements.txt
export PYTHONPATH=$PWD
python3 -m pytest isa/test_golden.py isa/test_random.py -q
python3 fw/programs.py
cd test && make
```

If you want 8×4 later, read [8x4.md](8x4.md). Do not grow the flop instruction memory; 128 words already cover the shipped protocols.

---

## 9. How to read the rest

| If you want… | Read |
| --- | --- |
| Word definitions (ASIC, GDS, PIO, …) | [beginner.md](beginner.md) |
| Exact opcodes | [../isa/SPEC.md](../isa/SPEC.md) |
| Why not PIO / why capture | [writeup.md](writeup.md) |
| Block diagram + area | [architecture.md](architecture.md) |
| Pinout and board test steps | [info.md](info.md) (Tiny Tapeout datasheet) |
| How we test | [verification.md](verification.md) |
| Cell count | [area.md](area.md) |

The circuit itself starts at [`src/tt_um_NarasingaUjjini_cycle.v`](../src/tt_um_NarasingaUjjini_cycle.v). Firmware starts at [`fw/programs.py`](../fw/programs.py).
