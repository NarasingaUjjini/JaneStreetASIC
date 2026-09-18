`default_nettype none
`timescale 1ns/1ps
`include "cycle_isa.vh"

// Icarus-friendly wrapper: after reset, outputs must be 0/1 not X.
module sim_wrap;
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0;
  wire [7:0] uo_out, uio_out, uio_oe;
  tt_um_NarasingaUjjini_cycle dut (
      .ui_in(8'h01),
      .uo_out(uo_out),
      .uio_in(8'h00),
      .uio_out(uio_out),
      .uio_oe(uio_oe),
      .ena(1'b1),
      .clk(clk),
      .rst_n(rst_n)
  );
  integer t;
  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1;
    for (t = 0; t < 50; t = t + 1) begin
      @(posedge clk);
      if (^uo_out === 1'bx) begin
        $display("FAIL X on uo_out");
        $fatal;
      end
      if (^uio_oe === 1'bx) begin
        $display("FAIL X on uio_oe");
        $fatal;
      end
    end
    $display("formal sim_wrap PASS");
    $finish;
  end
endmodule
