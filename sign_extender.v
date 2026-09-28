module sign_extender(
	output reg [31:0] ImmExt,
	input [31:0] Instr,
	input [2:0] ImmSrc);

always @(*)
	case(ImmSrc)
		3'b000: ImmExt = {{20{Instr[31]}}, Instr[31:20]};
		3'b001: ImmExt = {{20{Instr[31]}}, Instr[31:25], Instr[11:7]};
		3'b010: ImmExt = {{20{Instr[31]}}, Instr[7], Instr[30:25], Instr[11:8], 1'b0};
		3'b011: ImmExt = {{12{Instr[31]}}, Instr[19:12], Instr[20], Instr[30:21], 1'b0};
		3'b100: ImmExt = {Instr[31:12], 12'b0};
		3'b101: ImmExt = {27'b0, Instr[19:15]}; 
		default : ImmExt = 32'bx;
	endcase

endmodule
