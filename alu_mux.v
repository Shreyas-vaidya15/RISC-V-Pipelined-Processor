module alu_mux(
	output [31:0] B,
	input [31:0] RD2,
	input [31:0] csr_read_val,
	input [31:0] ImmExt,
	input ALUSrc, IsCSR
);

assign B = IsCSR ? csr_read_val : (ALUSrc ? ImmExt : RD2);

endmodule
