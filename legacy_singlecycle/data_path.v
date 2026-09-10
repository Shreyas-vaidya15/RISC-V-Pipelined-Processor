module data_path(
    output [31:0] ALUResult,
    output [31:0] WriteData,
    output Zero,
    output [31:0] PC,
    input clk,
    input reset,
    input [31:0] Instr,
    input [31:0] ReadData,
    input PCSrc,
    input [1:0] ResultSrc,
    input [3:0] ALUControl,
    input ALUSrc,
    input [2:0] ImmSrc,
    input RegWrite,
    output [31:0] RawALUResult,
    output [31:0] display_reg
);

wire [31:0] PCTarget;
wire [31:0] PCPlus4;
wire [31:0] PC_Next;
wire [31:0] ImmExt;
wire IsJalr = (Instr[6:0] == 7'b1100111);
wire IsAuipc = (Instr[6:0] == 7'b0010111);
wire [31:0] A = IsAuipc ? PC : rd1;
assign RawALUResult = Result;

reg [31:0] ReadDataExt;
always @(*) begin
    case (Instr[14:12])
        3'b000: ReadDataExt = {{24{ReadData[7]}},  ReadData[7:0]};   // lb  - sign-extend byte
        3'b001: ReadDataExt = {{16{ReadData[15]}}, ReadData[15:0]};  // lh  - sign-extend half
        3'b010: ReadDataExt = ReadData;                              // lw  - full word
        3'b100: ReadDataExt = {24'b0, ReadData[7:0]};                // lbu - zero-extend byte
        3'b101: ReadDataExt = {16'b0, ReadData[15:0]};               // lhu - zero-extend half
        default: ReadDataExt = ReadData;
    endcase
end

// Program counter block
pc_target pc_target(.PCTarget(PCTarget), .PC(PC), .ImmExt(ImmExt));
pc_mux pc_mux_inst(.PC_Next(PC_Next), .PC_Target(PCTarget), .PC_Plus_4(PCPlus4), .ALUResult(Result), .PCSrc(PCSrc), .IsJalr(IsJalr));
pc_plus_4 pc_plus_4_inst(.PCPlus4(PCPlus4), .PC(PC));
pc pc_inst(.PC(PC), .PCNext(PC_Next), .clk(clk), .reset(reset));

wire [31:0] rd1;
wire [31:0] rd2;
register_file registers(.rd1(rd1), .rd2(rd2), .clk(clk), .rs1(Instr[19:15]), .rs2(Instr[24:20]), .we(RegWrite), .wd(ALUResult), .wa(Instr[11:7]));

assign WriteData = rd2;

// ALU Wiring
wire [31:0] B;
wire [31:0] Result;
wire Overflow, Carry, Negative;
alu_mux alu_mux_inst(.B(B), .RD2(rd2), .ImmExt(ImmExt), .ALUSrc(ALUSrc));
alu alu_inst(.A(A), .B(B), .ALUControl(ALUControl), .Result(Result), .Zero(Zero), .Overflow(Overflow), .Carry(Carry), .Negative(Negative));
sign_extender sign_extender_inst(.ImmExt(ImmExt), .Instr(Instr), .ImmSrc(ImmSrc));

result_mux result_mux_inst(.Result(ALUResult), .ALUResult(Result), .ReadData(ReadDataExt), .PC_Plus_4(PCPlus4), .ResultSrc(ResultSrc));

endmodule