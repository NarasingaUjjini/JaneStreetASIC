# Cycle ISA specification

This is the frozen 16-bit encoding — the “vocabulary” of the tiny interpreter. Hardware (`src/cycle_isa.vh`), the assembler (`isa/encoding.py`), and the Python fake chip (`isa/golden.py`) must match. Tests fail if they drift.

Read the repository README first if you want the contest and a UART walkthrough in normal language. This file is the opcode list.

## Why an ISA instead of hardwired UART

A protocol is a sequence of: wait for a pin, drive a pin, wait N clocks, shift a bit. If those four actions are instructions, firmware can implement UART today and a weird camera bus tomorrow without a new chip. That is the whole contest.

Each **tick** is `clkdiv+1` system clocks. Default `clkdiv=0` means one instruction per clock (unless the instruction stalls: WAIT, FIFO, DELAY).

Instruction memory: 128 words × 16 bits, address 0..127. SM0 and SM1 fetch independently (dual-read flop RAM). By convention put SM0 at 0 and SM1 at 64 if you run both.

## Word format

```
15        12 11                            0
+-----------+-------------------------------+
|  opcode   | payload                       |
+-----------+-------------------------------+
```

| Opcode | Name | Payload |
| --- | --- | --- |
| 0 | JMP | `[11:9]` cond, `[8:0]` addr |
| 1 | WAIT | `[11]` polarity, `[10:8]` src, `[7:5]` index, `[4:0]` timeout_exp |
| 2 | IN | `[11:8]` count (0=16), `[7:5]` src |
| 3 | OUT | `[11:8]` count (0=16), `[7:5]` dest |
| 4 | MOV | `[11:9]` dest, `[8:6]` src, `[5:4]` op |
| 5 | SET | `[11:9]` dest, `[8:0]` imm |
| 6 | DELAY | `[11:0]` extra ticks (instruction occupies N+1 ticks) |
| 7 | FIFO | `[11]` 1=PULL TX→OSR, 0=PUSH ISR→RX; `[10]` iff (do not stall) |
| 8 | CRC | `[11:10]` cmd, `[9:8]` poly, `[7:0]` imm |
| 9 | IRQ | `[11]` wait, `[10]` clear, `[9:8]` index |
| A | CAP | `[11]` start, `[10]` edge, `[9:8]` trig pin, `[7:0]` period |
| B | PLAY | `[11]` start, `[10:0]` period |
| C | MODE | shift directions |
| D | NRZI | `[11]` enable, `[10]` bit-stuff |
| E | PIN | `[10:8]` index, `[7]` value, `[6]` oe |
| F | HALT | stop this SM until host RUN |

### JMP conditions

0 always, 1 X==0, 2 X-- (jump and decrement if X!=0), 3 Y==0, 4 Y--, 5 pin==1, 6 pin==0, 7 OSR empty.

`jmp_pin` is selected by `SET JMPPIN`.

### WAIT sources

0 pin[index]==polarity, 1 irq[index], 2 RX FIFO ready, 3 TX FIFO valid.
`timeout_exp=0` means wait forever. Else give up after `2^exp` ticks and set `wait_expired`.

### SET destinations

0 PINS, 1 X, 2 Y, 3 PINDIRS, 4 CLKDIV, 5 OUT_BASE, 6 IN_BASE, 7 JMP_PIN.

### OUT / IN

Default: OSR shifts **right** (LSB first, UART/SPI). ISR shifts **left** (new bit in at LSB).
`OUT 1, PINS` drives `out_base` with the bit that left the OSR.
`IN 1, PINS` samples `in_base`.

### Open-drain (I2C)

`PIN index, value=0, oe=1` pulls the net down.
`PIN index, value=0, oe=0` releases it (external pull-up makes a 1).
The top-level pin merge makes **low win** if both SMs drive.

### CRC

MSB-first byte update. Polynomials: CRC-8 `0x07`, CCITT-16 `0x1021`, USB-16 `0x8005`, CRC-5 `0x05`.

### NRZI

USB convention: data 0 = transition, data 1 = no change. Optional bit-stuff inserts a transition after six 1s.

## Timing contract (golden model)

1. `tick()` runs only when `running && !halted && prescale==clkdiv`.
2. If `delay_reg != 0`, decrement it and do not execute.
3. DELAY N sets `delay_reg=N` and increments PC. Total occupancy N+1 ticks.
4. WAIT does not increment PC until the condition (or timeout) is true.
5. PULL stalls when the TX FIFO is empty unless `iff`.

## What this is not

It is not a RISC-V. There is no data memory for C programs. If you need arithmetic, use X/Y and MOV INC. The point is **pins and time**, which is what PIO got right and general-purpose CPUs get wrong at this area.
