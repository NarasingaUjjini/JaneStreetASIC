// Formal-friendly pin safety. Also compiled by Icarus via sim_wrap.v
`default_nettype none

module pin_safety (
    input clk,
    input rst_n,
    input [7:0] uio_out,
    input [7:0] uio_oe
);
  integer i;
  always @(posedge clk) begin
    if (rst_n) begin
      for (i = 0; i < 8; i = i + 1) begin
        if (uio_oe[i] !== 1'b0 && uio_oe[i] !== 1'b1) $error("X on uio_oe");
        if (uio_out[i] !== 1'b0 && uio_out[i] !== 1'b1) $error("X on uio_out");
      end
    end
  end
endmodule
