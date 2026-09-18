# Synthesis area (Yosys 0.33, generic cells)

Target: **6×4 Tiny Tapeout tiles ≈ 24k cells**. CMOS5L has five metal layers, so we keep slack for clock-tree and routing. LibreLane `CLOCK_PERIOD` = 21 ns (~47.6 MHz), `PL_TARGET_DENSITY_PCT` = 50.

## Top-level `tt_um_NarasingaUjjini_cycle`

- **15,106 cells** after `synth` + `abc` (generic)
- Flip-flops: 2656 `$_DFFE_PP_` + 462 `$_DFFE_PN0P_` + 14 `$_DFFE_PN1P_` + 109 `$_DFF_PN0_` + 4 `$_DFF_PN1_` ≈ **3,245 sequential cells**
- Combinational: MUX 4291, AND 3206, NAND 3010, plus smaller gates

That is about **63% of a 24k-cell budget** before clock buffers. Room for an IHP 512×16 SRAM swap (replacing ~2k IMEM flops with a macro) if 8×4 unlocks or the CMOS5L template prefers macros.

Per-block (pre-flatten, Yosys `stat` on each module):

- `cycle_mem` (128×16 dual-read): ~6307 cells, 2048 enable-flops
- `cycle_sm` ×2: ~2366 cells each
- `cycle_capture` 64×8: ~3128 cells
- `cycle_host` + UARTs + FIFOs: a few hundred cells

Full GDS, DRC, LVS, STA, and **gate-level cocotb** run on GitHub Actions via `.github/workflows/gds.yaml` (`TinyTapeout/tt-gds-action@ihp-cmos5l`, PDK `ihp-sg13cmos5l`, from [ttihp-verilog-template@cmos5l](https://github.com/TinyTapeout/ttihp-verilog-template/tree/cmos5l)). Local flattened netlist: `build/synth.v` from `scripts/synth.sh`.
