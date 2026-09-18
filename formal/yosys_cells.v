// Minimal Yosys generic-cell models for local gate-level simulation.
`timescale 1ns/1ps
module \$_AND_ (A, B, Y); input A, B; output Y; assign Y = A & B; endmodule
module \$_NAND_ (A, B, Y); input A, B; output Y; assign Y = ~(A & B); endmodule
module \$_OR_ (A, B, Y); input A, B; output Y; assign Y = A | B; endmodule
module \$_NOR_ (A, B, Y); input A, B; output Y; assign Y = ~(A | B); endmodule
module \$_XOR_ (A, B, Y); input A, B; output Y; assign Y = A ^ B; endmodule
module \$_XNOR_ (A, B, Y); input A, B; output Y; assign Y = ~(A ^ B); endmodule
module \$_NOT_ (A, Y); input A; output Y; assign Y = ~A; endmodule
module \$_ANDNOT_ (A, B, Y); input A, B; output Y; assign Y = A & ~B; endmodule
module \$_ORNOT_ (A, B, Y); input A, B; output Y; assign Y = A | ~B; endmodule
module \$_MUX_ (A, B, S, Y); input A, B, S; output Y; assign Y = S ? B : A; endmodule

module \$_DFF_PN0_ (C, R, D, Q);
  input C, R, D; output reg Q;
  always @(posedge C or negedge R) if (!R) Q <= 1'b0; else Q <= D;
endmodule
module \$_DFF_PN1_ (C, R, D, Q);
  input C, R, D; output reg Q;
  always @(posedge C or negedge R) if (!R) Q <= 1'b1; else Q <= D;
endmodule
module \$_DFFE_PP_ (C, E, D, Q);
  input C, E, D; output reg Q;
  always @(posedge C) if (E) Q <= D;
endmodule
module \$_DFFE_PN0P_ (C, R, E, D, Q);
  input C, R, E, D; output reg Q;
  always @(posedge C or negedge R) if (!R) Q <= 1'b0; else if (E) Q <= D;
endmodule
module \$_DFFE_PN1P_ (C, R, E, D, Q);
  input C, R, E, D; output reg Q;
  always @(posedge C or negedge R) if (!R) Q <= 1'b1; else if (E) Q <= D;
endmodule
