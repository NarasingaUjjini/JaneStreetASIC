// Copyright (c) 2026 Narasinga Ujjini
// SPDX-License-Identifier: Apache-2.0
//
// Cycle: a reprogrammable protocol-emulator ASIC for the Jane Street
// Tiny Tapeout CMOS5L competition.
//
// After reset the chip listens on the host UART (ui[0] RX, uo[0] TX).
// Load 16-bit Cycle instructions, then RUN. Two state machines wiggle
// uio[7:0] with cycle-accurate timing. Capture/replay lives alongside.

`default_nettype none

module tt_um_NarasingaUjjini_cycle (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
  localparam ADDR_W = 7;
  localparam BAUD_DIV = 8;

  wire host_rx = ui_in[0];
  wire trigger = ui_in[1];

  wire [6:0] sm0_addr, sm1_addr;
  wire [15:0] sm0_rdata, sm1_rdata;
  wire mem_we;
  wire [6:0] mem_waddr;
  wire [15:0] mem_wdata;

  cycle_mem #(
      .DEPTH (128),
      .ADDR_W(ADDR_W)
  ) u_mem (
      .clk   (clk),
      .we    (mem_we),
      .waddr (mem_waddr),
      .wdata (mem_wdata),
      .addr0 (sm0_addr),
      .rdata0(sm0_rdata),
      .addr1 (sm1_addr),
      .rdata1(sm1_rdata)
  );

  wire running, go0, go1, set_pc0, set_pc1;
  wire [6:0] pc_val;
  wire sm0_halted, sm1_halted;
  wire [7:0] sm0_pout, sm1_pout, sm0_oe, sm1_oe;
  wire [7:0] sm0_dbg_pc, sm1_dbg_pc, sm0_dbg_x, sm1_dbg_x;

  wire tx0_valid, tx0_ready, rx0_valid, rx0_ready;
  wire tx1_valid, tx1_ready, rx1_valid, rx1_ready;
  wire [7:0] tx0_data, rx0_data, tx1_data, rx1_data;

  wire [3:0] irq0_set, irq0_clr, irq1_set, irq1_clr;
  reg  [3:0] irq;
  wire cap0_start, cap0_stop, play0_start, play0_stop;
  wire cap1_start, cap1_stop, play1_start, play1_stop;
  wire [7:0] cap0_period, cap1_period;
  wire cap0_edge, cap1_edge;
  wire [1:0] cap0_trig, cap1_trig;

  wire host_cap_start, host_cap_stop, host_play_start;

  cycle_sm #(.ADDR_W(ADDR_W)) u_sm0 (
      .clk        (clk),
      .rst_n      (rst_n),
      .running    (running),
      .go         (go0),
      .set_pc     (set_pc0),
      .pc_in      (pc_val),
      .halted     (sm0_halted),
      .imem_addr  (sm0_addr),
      .imem_rdata (sm0_rdata),
      .pins_in    (uio_in),
      .pins_out   (sm0_pout),
      .pins_oe    (sm0_oe),
      .tx_valid   (tx0_valid),
      .tx_data    (tx0_data),
      .tx_ready   (tx0_ready),
      .rx_valid   (rx0_valid),
      .rx_data    (rx0_data),
      .rx_ready   (rx0_ready),
      .irq_in     (irq),
      .irq_set    (irq0_set),
      .irq_clr    (irq0_clr),
      .cap_start  (cap0_start),
      .cap_stop   (cap0_stop),
      .play_start (play0_start),
      .play_stop  (play0_stop),
      .cap_period (cap0_period),
      .cap_edge   (cap0_edge),
      .cap_trig   (cap0_trig),
      .dbg_pc     (sm0_dbg_pc),
      .dbg_x      (sm0_dbg_x)
  );

  cycle_sm #(.ADDR_W(ADDR_W)) u_sm1 (
      .clk        (clk),
      .rst_n      (rst_n),
      .running    (running),
      .go         (go1),
      .set_pc     (set_pc1),
      .pc_in      (pc_val),
      .halted     (sm1_halted),
      .imem_addr  (sm1_addr),
      .imem_rdata (sm1_rdata),
      .pins_in    (uio_in),
      .pins_out   (sm1_pout),
      .pins_oe    (sm1_oe),
      .tx_valid   (tx1_valid),
      .tx_data    (tx1_data),
      .tx_ready   (tx1_ready),
      .rx_valid   (rx1_valid),
      .rx_data    (rx1_data),
      .rx_ready   (rx1_ready),
      .irq_in     (irq),
      .irq_set    (irq1_set),
      .irq_clr    (irq1_clr),
      .cap_start  (cap1_start),
      .cap_stop   (cap1_stop),
      .play_start (play1_start),
      .play_stop  (play1_stop),
      .cap_period (cap1_period),
      .cap_edge   (cap1_edge),
      .cap_trig   (cap1_trig),
      .dbg_pc     (sm1_dbg_pc),
      .dbg_x      (sm1_dbg_x)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) irq <= 4'd0;
    else irq <= (irq | irq0_set | irq1_set) & ~(irq0_clr | irq1_clr);
  end

  wire tx0_full, tx0_empty, rx0_full, rx0_empty;
  wire tx1_full, tx1_empty, rx1_full, rx1_empty;
  wire host_fifo_we;
  wire [7:0] host_fifo_wdata;
  wire host_fifo_re;
  wire [7:0] host_fifo_rdata;

  cycle_fifo u_tx0 (
      .clk  (clk),
      .rst_n(rst_n),
      .we   (host_fifo_we),
      .wdata(host_fifo_wdata),
      .re   (tx0_ready),
      .rdata(tx0_data),
      .empty(tx0_empty),
      .full (tx0_full)
  );
  assign tx0_valid = ~tx0_empty;

  cycle_fifo u_rx0 (
      .clk  (clk),
      .rst_n(rst_n),
      .we   (rx0_valid),
      .wdata(rx0_data),
      .re   (host_fifo_re),
      .rdata(host_fifo_rdata),
      .empty(rx0_empty),
      .full (rx0_full)
  );
  assign rx0_ready = ~rx0_full;

  // SM1 FIFOs loop to each other so SM1 can still PUSH/PULL in isolation.
  cycle_fifo u_tx1 (
      .clk  (clk),
      .rst_n(rst_n),
      .we   (rx1_valid),
      .wdata(rx1_data),
      .re   (tx1_ready),
      .rdata(tx1_data),
      .empty(tx1_empty),
      .full (tx1_full)
  );
  assign tx1_valid = ~tx1_empty;
  assign rx1_ready = ~tx1_full;

  wire capturing, playing, cap_full;
  wire [7:0] pins_play, oe_play, cap_host_rdata;
  wire [6:0] cap_count;
  wire cap_re;

  wire [7:0] cap_period_mux = cap0_start ? cap0_period : (cap1_start ? cap1_period : 8'd0);
  wire cap_edge_mux = cap0_start ? cap0_edge : cap1_edge;
  wire [1:0] cap_trig_mux = cap0_start ? cap0_trig : cap1_trig;

  cycle_capture u_cap (
      .clk       (clk),
      .rst_n     (rst_n),
      .cap_start (cap0_start | cap1_start | host_cap_start),
      .cap_stop  (cap0_stop | cap1_stop | host_cap_stop),
      .play_start(play0_start | play1_start | host_play_start),
      .play_stop (play0_stop | play1_stop),
      .period    (cap_period_mux),
      .edge_mode (cap_edge_mux),
      .trig_pin  (cap_trig_mux),
      .pins_in   (uio_in),
      .capturing (capturing),
      .playing   (playing),
      .full      (cap_full),
      .pins_play (pins_play),
      .oe_play   (oe_play),
      .host_re   (cap_re),
      .host_rdata(cap_host_rdata),
      .count     (cap_count)
  );

  // Pin merge: either SM (or replay) may pull a pin down. Low wins.
  wire [7:0] drive_low  = (sm0_oe & ~sm0_pout) | (sm1_oe & ~sm1_pout) | (oe_play & ~pins_play);
  wire [7:0] drive_high = (sm0_oe & sm0_pout) | (sm1_oe & sm1_pout) | (oe_play & pins_play);
  assign uio_oe  = drive_low | drive_high;
  assign uio_out = drive_high & ~drive_low;

  wire uart_rx_valid, uart_tx_busy, uart_tx_we;
  wire [7:0] uart_rx_data, uart_tx_data;
  wire uart_rx_ready;
  wire host_tx;

  cycle_uart_rx #(.BAUD_DIV(BAUD_DIV)) u_urx (
      .clk  (clk),
      .rst_n(rst_n),
      .rx   (host_rx),
      .valid(uart_rx_valid),
      .data (uart_rx_data),
      .ready(uart_rx_ready)
  );

  cycle_uart_tx #(.BAUD_DIV(BAUD_DIV)) u_utx (
      .clk  (clk),
      .rst_n(rst_n),
      .we   (uart_tx_we),
      .wdata(uart_tx_data),
      .busy (uart_tx_busy),
      .tx   (host_tx)
  );

  cycle_host u_host (
      .clk          (clk),
      .rst_n        (rst_n),
      .rx_valid     (uart_rx_valid),
      .rx_data      (uart_rx_data),
      .rx_ready     (uart_rx_ready),
      .tx_we        (uart_tx_we),
      .tx_data      (uart_tx_data),
      .tx_busy      (uart_tx_busy),
      .mem_we       (mem_we),
      .mem_addr     (mem_waddr),
      .mem_wdata    (mem_wdata),
      .running      (running),
      .go0          (go0),
      .go1          (go1),
      .set_pc0      (set_pc0),
      .set_pc1      (set_pc1),
      .pc_val       (pc_val),
      .fifo_we      (host_fifo_we),
      .fifo_wdata   (host_fifo_wdata),
      .fifo_full    (tx0_full),
      .fifo_re      (host_fifo_re),
      .fifo_rdata   (host_fifo_rdata),
      .fifo_empty   (rx0_empty),
      .sm0_halted   (sm0_halted),
      .sm1_halted   (sm1_halted),
      .capturing    (capturing),
      .playing      (playing),
      .cap_start    (host_cap_start),
      .cap_stop     (host_cap_stop),
      .play_start   (host_play_start),
      .cap_rdata    (cap_host_rdata),
      .cap_re       (cap_re)
  );

  assign uo_out[0] = host_tx;
  assign uo_out[1] = running;
  assign uo_out[2] = ~rx0_empty;
  assign uo_out[3] = tx0_full;
  assign uo_out[4] = sm0_halted;
  assign uo_out[5] = sm1_halted;
  assign uo_out[6] = capturing | playing;
  assign uo_out[7] = cap_full;

  wire _unused = &{ena, trigger, ui_in[7:2], sm0_dbg_pc, sm1_dbg_pc, sm0_dbg_x, sm1_dbg_x,
                   cap1_period, cap1_edge, cap1_trig, cap_count, tx1_ready, rx1_data, 1'b0};
endmodule
