# Architecture

```
 ui[0] HOST_RX ── UART RX ── host FSM ── write 128x16 RAM
 uo[0] HOST_TX ── UART TX ─┘           ├── SM0 ──┐
                                       └── SM1 ──┤
                                                 ▼
                                            pin merge (0 wins)
                                                 ▼
                                              uio[7:0]

 SM CAP/PLAY ── 64 x 8 capture RAM ── UART dump / pin replay
 SM0 TX/RX FIFOs ── host WFIFO / RFIFO
 IRQ[3:0] shared between SMs
 CRC-8/16 and NRZI live inside each SM
```

## Area plan (6×4 = ~24 tiles, ~1k cells/tile)

| Block | Estimate | Notes |
| --- | --- | --- |
| 128×16 flop IMEM | ~2k FFs | Fits; SRAM optional upgrade |
| 2 × SM | ~800 cells each | 16-bit ISA |
| 2 × UART | small | host only |
| 4-deep FIFOs | ~100 FFs | |
| Capture 64×8 | ~512 FFs | |
| Host + merge | small | |

If 8×4 unlocks: instantiate `cycle_sram_ihp` at 512×16 and keep the flop RAM as a cache, or deepen capture to 512 samples.

## Clock

LibreLane `CLOCK_PERIOD` is 21 ns (~47.6 MHz), close to the 48 MHz USB-LS-friendly board clock. Host `BAUD_DIV=8` is a simulation convenience; change the parameter for 115200 (`48e6/115200 ≈ 417`).
