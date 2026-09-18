#!/usr/bin/env bash
# Yosys synthesis for Cycle. Writes build/synth.v and build/synth.log.
# docs/area.md is the committed CMOS5L writeup — do not clobber it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
cd "$ROOT"

# Do not pass -q: `stat` must land in build/synth.log.
yosys -p "
read_verilog -I src src/cycle_mem.v src/cycle_fifo.v src/cycle_uart_rx.v src/cycle_uart_tx.v src/cycle_host.v src/cycle_sm.v src/cycle_capture.v src/tt_um_NarasingaUjjini_cycle.v
hierarchy -check -top tt_um_NarasingaUjjini_cycle
proc; opt
memory; opt
techmap; opt
abc
opt_clean
stat -top tt_um_NarasingaUjjini_cycle
write_verilog -noattr build/synth.v
" | tee build/synth.log

python3 - <<'PY'
from pathlib import Path
log = Path("build/synth.log").read_text()
Path("build/area_stat.md").write_text(
    "# Local Yosys stat (generic cells)\n\n"
    "6×4 Tiny Tapeout tiles is roughly 24k cells of budget. "
    "CMOS5L has 5 metals — leave slack for routing.\n\n"
    "```\n" + log.strip() + "\n```\n\n"
    "LibreLane `CLOCK_PERIOD` = 21 ns, `PL_TARGET_DENSITY_PCT` = 50. "
    "Full GDS/timing comes from `.github/workflows/gds.yaml` on GitHub Actions "
    "(`TinyTapeout/tt-gds-action@ihp-cmos5l`, PDK `ihp-sg13cmos5l`, from "
    "[ttihp-verilog-template@cmos5l](https://github.com/TinyTapeout/ttihp-verilog-template/tree/cmos5l)).\n"
)
print(Path("build/area_stat.md").read_text())
PY
