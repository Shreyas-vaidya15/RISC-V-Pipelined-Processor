module control_path(
    input [31:0] Instr,
	input Zero,
	input [31:0] ALUResult,
    output RegWrite,
	output [2:0] ImmSrc,
	output ALUSrc,
	output MemWrite,
	output [1:0] ResultSrc,
	output PCSrc,
    output [3:0] ALUControl,
	output Jump
);


wire [1:0] ALUOp;
wire Branch;
wire Jump_internal;
assign Jump = Jump_internal;
wire BranchDecision = Instr[14] ? ALUResult[0] : Zero;
assign PCSrc = Jump_internal | (Branch & (BranchDecision ^ Instr[12]));

main_decoder inst1(.RegWrite(RegWrite), .ImmSrc(ImmSrc), .ALUSrc(ALUSrc), .MemWrite(MemWrite), .ResultSrc(ResultSrc), .Branch(Branch), .ALUop(ALUOp), .Jump(Jump_internal), .op(Instr[6:0]));
alu_decoder inst2(.ALUOp(ALUOp), .funct3(Instr[14:12]), .funct7b5(Instr[30]), .opb5(Instr[5]), .ALUControl(ALUControl));

endmodule