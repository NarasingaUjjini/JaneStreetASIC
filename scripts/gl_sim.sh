#!/usr/bin/env bash
# Local gate-level sim of Yosys generic netlist (not IHP stdcells).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
test -f "$ROOT/build/synth.v" || "$ROOT/scripts/synth.sh"
cd "$ROOT"
iverilog -g2012 -o /tmp/cycle_gl formal/yosys_cells.v build/synth.v formal/gl_tb.v
vvp /tmp/cycle_gl
