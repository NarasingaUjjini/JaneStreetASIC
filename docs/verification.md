# Verification

Jane Street’s announcement said verification matters more as AI writes more RTL. This entry treats the generator as hostile.

## Layers

1. **Spec = Python.** `isa/golden.py` implements every opcode. `isa/test_golden.py` checks DELAY occupancy, XDEC loop count, and that the UART TX program emits `0x55` 8N1. Run: `python3 -m pytest isa/test_golden.py isa/test_random.py -q`

2. **Constrained random.** `isa/test_random.py` draws legal instruction soup, runs N ticks on the golden model, and asserts the machine does not crash (PC stays in range, pin dirs are 8-bit). A second mode (when Icarus is present) compares `dbg_pc` / `dbg_x` hierarchically — see cocotb tests.

3. **Directed protocol tests** (`test/test.py`, cocotb + Icarus):
   - Host UART status
   - UART TX `0x55` on `uio[0]`
   - SPI master CS/SCLK
   - I2C START is open-drain (never drives 1)
   - Capture flag
   - JTAG TCK toggles

4. **Formal pin safety** (`formal/pin_safety.sv` + `formal/pin_safety.sby`). Properties:
   - `uio_oe[i] && uio_out[i]` can happen for push-pull firmware, but I2C programs only drive 0 — checked in sim.
   - No X on outputs after reset.
   - HALT implies `dbg_pc` stable if `running` stays 1 without GO.
   SymbiYosys is optional; the same asserts are instantiated in `formal/sim_wrap.v` for Icarus.

5. **Synthesis.** `scripts/synth.sh` runs Yosys `synth` and writes `docs/area.md`. Budget: 6×4 tiles ≈ 24k cells; we keep slack for CMOS5L’s five metal layers (target density 50%).

6. **Gate-level.** Tiny Tapeout `gds.yaml` GL job (`tt-gds-action@ihp-cmos5l`) simulates the LibreLane CMOS5L netlist. `test/Makefile` must compile `sg13cmos5l_udp.v` before the stdcells (they instantiate `ihp_mux2` / `ihp_mux4`). Locally, `scripts/synth.sh` also writes `build/synth.v`.

## AI-assisted, adversarial

RTL in this repo was written with an AI coding agent. That is on-theme: the contest text lists “AI-assisted verification.” We do **not** ask a model “is the UART correct?” and believe it. We:

- freeze the ISA on paper first
- implement the golden model independently of the Verilog
- keep tests that would fail if the agent inverted start-bit polarity or used X as both a bit and a loop counter (it did; I2C firmware was fixed)

If you change an opcode, change `cycle_isa.vh`, `encoding.py`, and `golden.py` in the same commit.
