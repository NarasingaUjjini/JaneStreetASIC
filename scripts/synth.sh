#!/usr/bin/env bash
# Yosys synthesis for Cycle. Writes docs/area.md and build/synth.v
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
cd "$ROOT"

yosys -q -p "
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
Path("docs/area.md").write_text(
    "# Synthesis area (Yosys 0.33, generic cells)\n\n"
    "6×4 Tiny Tapeout tiles is roughly 24k cells of budget. "
    "CMOS5L has 5 metals — leave slack for routing.\n\n"
    "```\n" + log.strip() + "\n```\n\n"
    "LibreLane `CLOCK_PERIOD` = 21 ns, `PL_TARGET_DENSITY_PCT` = 50. "
    "Full GDS/timing comes from `.github/workflows/gds.yaml` on GitHub Actions "
    "(Tiny Tapeout `ttihp26b` until the CMOS5L template is published).\n"
)
print(Path("docs/area.md").read_text())
PY
