`timescale 1ns/1ps
module gl_tb;
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0;
  wire [7:0] uo_out, uio_out, uio_oe;
  tt_um_NarasingaUjjini_cycle dut (
    .ui_in(8'h01), .uo_out(uo_out), .uio_in(8'h00),
    .uio_out(uio_out), .uio_oe(uio_oe), .ena(1'b1), .clk(clk), .rst_n(rst_n)
  );
  integer t;
  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1;
    for (t = 0; t < 30; t = t + 1) begin
      @(posedge clk);
      if (^uo_out === 1'bx || ^uio_oe === 1'bx) begin
        $display("GL FAIL X");
        $fatal;
      end
    end
    $display("GL sim PASS uo=%h oe=%h", uo_out, uio_oe);
    $finish;
  end
endmodule
