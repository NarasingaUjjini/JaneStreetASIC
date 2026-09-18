#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
iverilog -g2012 -I src -o /tmp/cycle_formal_wrap \
  src/cycle_mem.v src/cycle_fifo.v src/cycle_uart_rx.v src/cycle_uart_tx.v \
  src/cycle_host.v src/cycle_sm.v src/cycle_capture.v \
  src/tt_um_NarasingaUjjini_cycle.v formal/sim_wrap.v
vvp /tmp/cycle_formal_wrap
