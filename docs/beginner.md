# Beginner glossary (no prior chip experience required)

You are not writing an app. You are describing a **circuit** that a factory will etch in silicon.

**ASIC** — Application-Specific Integrated Circuit. A chip whose transistors are fixed at manufacture. You cannot add a new UART block later. You *can* add a tiny programmable engine, which is this project.

**RTL** — Register-Transfer Level. Verilog files that say “on this clock edge, this register becomes that.” `src/*.v` is RTL.

**Clock** — A square wave from the board. Every rising edge, registers update. We target 48 MHz (48 million edges per second).

**Reset** — `rst_n` is active-low: 0 means “go back to the start,” 1 means “run.”

**Pin / GPIO** — A wire off the chip. Tiny Tapeout gives you 8 inputs (`ui`), 8 outputs (`uo`), and 8 bidirectional (`uio`). You cannot add more.

**Open-drain** — Drive 0 or let go. I2C uses this so two chips can share a wire with a resistor pulling it up to 1.

**Protocol** — An agreement about what pin wiggles mean. UART: idle 1, start 0, eight bits, stop 1. SPI: a clock pin and a data pin. I2C: two open-drain wires.

**Firmware vs hardware** — Hardware is the ISA (the transistors). Firmware is a list of 16-bit instructions in RAM. After fabrication you change firmware, not hardware.

**Synthesis** — Yosys turns RTL into a netlist of standard cells (NANDs, flip-flops from the foundry library).

**Place and route** — A tool puts those cells on the 6×4 tile rectangle and draws metal wires. CMOS5L has only five metal layers, so crowding fails even if synthesis said “it fits.”

**GDS** — The file the factory uses. Tiny Tapeout’s GitHub Action builds it from this repo.

**PIO** — Programmable I/O on the Raspberry Pi RP2040. Jane Street said “look at that, then do something different.” Our difference is capture/replay plus CRC/NRZI helpers plus a verification stack that does not trust the generator.

**Golden model** — A Python program that is the law for what each instruction does. RTL must match it.

**Formal verification** — A solver tries to find any input that breaks a rule (for example “open-drain never drives 1”). If it cannot, the rule holds for all cases, not just the tests we thought of.

**Tapeout** — Sending GDS to the foundry. Jane Street pays for winners on the March 2027 shuttle. You get a real chip on a board months later.
