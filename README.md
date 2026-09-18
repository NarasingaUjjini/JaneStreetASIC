![gds](https://github.com/NarasingaUjjini/JaneStreetASIC/actions/workflows/gds.yaml/badge.svg) ![docs](https://github.com/NarasingaUjjini/JaneStreetASIC/actions/workflows/docs.yaml/badge.svg) ![test](https://github.com/NarasingaUjjini/JaneStreetASIC/actions/workflows/test.yaml/badge.svg) ![fpga](https://github.com/NarasingaUjjini/JaneStreetASIC/actions/workflows/fpga.yaml/badge.svg)

# Cycle

This repo is a contest entry: we are trying to get a **real, tiny chip** manufactured.

If you have never seen chip design before, stay on this page. Everything you need to understand the project is here. The other files under `docs/` are notes for the contest judges and for the factory tools, not a second beginner track.

## What the contest is

[Jane Street](https://blog.janestreet.com/protocol-emulator-asic-competition/) (a trading firm with a hardware team) will pay to fabricate a few open-source student/hobby chips. Deadline: **18 January 2027**. If they pick this design, a foundry etches it in 2027 and a board shows up in the mail.

They do **not** want “a UART chip + an SPI chip + an I2C chip on one die.” Those names are just examples of *how computers wiggle wires*. They want a chip you can **reprogram after it is already made**, so it can learn a new wire-wiggling language without a second factory run.

## What a chip even is (the 30-second version)

A Python script can flip a Raspberry Pi pin whenever it wants. A finished **ASIC** (the kind of chip a factory stamps out of silicon) cannot download a new Python script. Its transistors are frozen.

So if you hard-wire “this pin is UART” into the silicon, it is UART forever. The trick is to freeze something more like a **tiny interpreter**: a handful of instructions that only know how to wait on a pin, drive a pin, shift a bit, and count clock ticks. After you have the physical chip, you load a short program into on-chip memory. That program *is* UART, or SPI, or something nobody has named yet.

That program is not C. It is not an operating system. Think of it as a recipe with sixteen kinds of steps, all about pins and time.

Cycle is that interpreter, plus a **tape recorder for the pins** (capture and replay). Record what some mystery gadget did, dump the recording, play it back. That is the reverse-engineering trick, and it is the part that is not a clone of the Raspberry Pi’s PIO.

The factory process is IHP 130 nm **CMOS5L**, through [Tiny Tapeout](https://tinytapeout.com). Jane Street gave every team a rectangle of **6×4 tiles** (about 0.7 mm²). The chip’s official name is `tt_um_NarasingaUjjini_cycle`.

## The wires we are allowed to touch

Tiny Tapeout puts every student project in the same cage. We cannot add pins.

- **`clk`** — a metronome from the board. On every tick, the circuit is allowed to change. We aim for 48 million ticks per second (48 MHz) on the real board.
- **`rst_n`** — hold this at 0 and the chip forgets everything and goes back to “halted.” (`_n` means “active when low.”)
- **`ui[0]` … `ui[7]`** — eight input-only wires. We use `ui[0]` as “laptop talking to the chip” and `ui[1]` as an optional trigger. The rest are unused.
- **`uo[0]` … `uo[7]`** — eight output-only wires. `uo[0]` is “chip talking back to the laptop.” The others are status lights (running, FIFO full, capture on, …).
- **`uio[0]` … `uio[7]`** — eight wires that can be input *or* output. **These are the protocol pins.** Firmware decides “pin 0 is UART transmit” or “pin 0 is SPI clock.” Same eight wires, different recipes.

A laptop (or the Tiny Tapeout board’s RP2040 microcontroller) talks to Cycle on `ui[0]` / `uo[0]` using ordinary serial bytes. Every command starts with the byte `0xA5` so the chip can tell a real command from noise.

## A worked example: send the number 85 as UART

`85` in decimal is `0x55` in hex, which is `01010101` in binary. UART on one wire means:

1. Sit at 1 when nothing is happening (idle).
2. Drop to 0 for one bit-time (the start bit: “hey, a byte is coming”).
3. Send eight data bits, **least-significant bit first**.
4. Go back to 1 (the stop bit).

The recipe for that lives in `fw/programs.py` as `uart_tx()`. In English it says:

1. Pin 0 is an output. Park it at 1.
2. Wait until the laptop gives me a byte (`PULL`).
3. Drive pin 0 to 0 (start).
4. Eight times: dump one bit onto pin 0, then loop (`OUT` + `JMP` that counts down X).
5. Drive pin 0 to 1 (stop).
6. Go back to step 2.

The transistors on the chip do **not** contain a UART block. They contain wait / drive / shift / delay. SPI firmware in the same file uses the same instructions to toggle a clock and a chip-select. I2C firmware only ever drives 0, then lets go — because I2C shares wires with a resistor pulling them up to 1, and two chips must not fight by both driving 1.

After the chip is manufactured, a new protocol is a new recipe, not a new shuttle.

To actually run that UART recipe you (or a test) do:

1. Reset the chip.
2. Send each 16-bit instruction into memory: `A5 01 <address> <low byte> <high byte>`.
3. `A5 02` — start state machine 0.
4. `A5 04 55` — hand it the byte `0x55`.
5. Watch `uio[0]` do start, `1 0 1 0 1 0 1 0`, stop.

`test/test.py` function `test_uart_tx_byte` is exactly that, in a simulator so we do not need a factory first.

There are two state machines (SM0 and SM1) so one can talk while the other listens. `A5 02` starts **only SM0**. `A5 0E` starts SM1. If both run the same program they fight over the pins (a 0 from either one wins, which is what I2C needs, and which will sit on an SPI clock and never let it rise). Unused memory starts as HALT so a sleeping machine does not drive anything.

## How we know this is not wishful thinking

An AI agent wrote most of the Verilog (the circuit description in `src/`). Jane Street specifically asked for verification, including AI-assisted verification. So we treat that Verilog as a suspect:

1. `isa/golden.py` is a Python fake of the same instruction set. If Python and Verilog disagree, **Verilog is wrong**.
2. Tests load the real UART / SPI / I2C / JTAG recipes and look at the pins.
3. Random legal programs must not crash (the program counter stays inside 0…127).
4. GitHub draws the actual silicon layout (GDS) and then tries to simulate *that* netlist, not the pretty Verilog.

A real bug this caught: early I2C firmware used one register as both “the data bits” and “how many times to loop,” so the loop smashed the data. The loop counter is a different register now.

Run the same checks on your laptop (free tools):

```bash
sudo apt-get install -y iverilog yosys python3-pip
pip install -r test/requirements.txt
export PYTHONPATH=$PWD
python3 -m pytest isa/test_golden.py isa/test_random.py -q
python3 fw/programs.py          # writes fw/*.hex
cd test && make                 # watch the pins in simulation
```

The colored badges at the top of this README are GitHub running those jobs, plus the factory layout. Green `test` means the simulator still agrees. Green `gds` means the layout tool finished. The first GDS run takes a couple of hours; that is the computer placing tens of thousands of gates and drawing metal.

## What the folders are

| Folder | In one sentence |
| --- | --- |
| `src/` | The circuit. `tt_um_NarasingaUjjini_cycle.v` is the top. Tiny Tapeout requires that exact pin list. |
| `fw/` | Example recipes (UART, SPI, I2C, JTAG, SWD, capture, a USB-low-speed helper). |
| `isa/` | What each 16-bit instruction means, plus the Python fake chip. |
| `test/` | Pretend the chip exists, load a recipe, check the pins. |
| `formal/` | Extra rules of the form “this should be impossible.” |
| `docs/` | Judge / factory notes (`info.md` is the Tiny Tapeout datasheet). |
| `.github/workflows/` | The official CMOS5L Tiny Tapeout actions that draw GDS. |

Opcodes: [`isa/SPEC.md`](isa/SPEC.md). Layout cell count: [`docs/area.md`](docs/area.md). If Jane Street unlocks a bigger rectangle: [`docs/8x4.md`](docs/8x4.md).

Public copy of this repo: [github.com/NarasingaUjjini/JaneStreetASIC](https://github.com/NarasingaUjjini/JaneStreetASIC). Layout viewer (after GDS): [narasingaujjini.github.io/JaneStreetASIC](https://narasingaujjini.github.io/JaneStreetASIC/).

Do **not** fill a Jane Street “final submit” form yet — they said that form appears closer to the deadline. Until then, this GitHub repo *is* the entry.

## Host command cheat sheet

8N1 serial on `ui[0]` (into the chip) and `uo[0]` (out of the chip). Every command starts with `0xA5`.

| After `A5` | Meaning |
| --- | --- |
| `01 addr lo hi` | Write one 16-bit instruction |
| `02` | Run SM0 |
| `03` | Halt |
| `04 data` | Push a byte into SM0’s TX FIFO |
| `05` | Pop SM0’s RX FIFO (chip replies with the byte) |
| `06` | Status byte |
| `07 sm pc` | Set program counter |
| `09` / `0A` / `0B` | Capture on / off / read one sample |
| `0C` | Replay the capture |
| `0E` | Run SM1 |

Firmware pin maps are at the top of `fw/programs.py`. LibreLane (the layout tool) is told 21 ns per clock and 50% placement density so five metal layers have room to route. Tile size in `info.yaml` is `6x4`, which Jane Street required. Template: [ttihp-verilog-template@cmos5l](https://github.com/TinyTapeout/ttihp-verilog-template/tree/cmos5l).

License: Apache-2.0.
