module riscv(
    input [31:0] Instr,
    input clk,
    input reset,
    input [31:0] ReadData,
    output [31:0] ALUResult,
    output [31:0] WriteData,
    output [31:0] PC,
    output MemWrite,
    output [31:0] RawALUResult,
    output [31:0] display_reg
);

wire Zero; // Output from data path to control path
wire RegSrc;
wire [1:0] ResultSrc;
wire [3:0] ALUControl;
wire ALUSrc;
wire [2:0] ImmSrc;
wire RegWrite;
wire Jump;
wire PCSrc;

data_path dp(.ALUResult(ALUResult), 
                .WriteData(WriteData), 
                .Zero(Zero), 
                .PC(PC), 
                .clk(clk), 
                .reset(reset), 
                .Instr(Instr), 
                .ReadData(ReadData), 
                .PCSrc(PCSrc), 
                .ResultSrc(ResultSrc), 
                .ALUControl(ALUControl), 
                .RawALUResult(RawALUResult),
                .ALUSrc(ALUSrc), 
                .ImmSrc(ImmSrc), 
                .RegWrite(RegWrite),
                .display_reg(display_reg));

control_path cp(.Instr(Instr), 
                   .RegWrite(RegWrite), 
                   .ImmSrc(ImmSrc), 
                   .ALUSrc(ALUSrc),
                   .MemWrite(MemWrite),
                   .ResultSrc(ResultSrc),
                   .PCSrc(PCSrc),
                   .Zero(Zero),
                   .ALUResult(ALUResult),
                   .ALUControl(ALUControl));

endmodule