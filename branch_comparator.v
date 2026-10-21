module branch_comparator
(
    input  [31:0] A,
    input  [31:0] B,
    input  [2:0]  funct3,
    output        condition
);

wire eq        = (A == B);
wire lt_signed = ($signed(A) < $signed(B));
wire lt_unsign = (A < B);

assign condition = funct3[2] ? (funct3[1] ? lt_unsign : lt_signed) : eq;

endmodule