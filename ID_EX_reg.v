module ID_EX_reg
(
    input clk, reset, Flush, Stall,
    input [31:0] PC_In, PC_Plus_4_In, RD1_In, RD2_In, ImmExt_In, Instr_In,
    input [4:0] WA_In,
    input [3:0] ALUControl_In,
    input [1:0] ResultSrc_In,
    input RegWrite_In, ALUSrc_In, MemWrite_In, Branch_In, Jump_In, Predicted_Taken_In,
    output reg [31:0] PC_Out, PC_Plus_4_Out, RD1_Out, RD2_Out, ImmExt_Out, Instr_Out,
    output reg [4:0] WA_Out,
    output reg [3:0] ALUControl_Out,
    output reg [2:0] Funct3_Out,
    output reg [1:0] Width_Out, ResultSrc_Out,
    output reg RegWrite_Out, ALUSrc_Out, MemWrite_Out, Branch_Out, Jump_Out, Predicted_Taken_Out
);

always @(posedge clk or posedge reset)
begin

    if (reset | Flush | Stall)
    begin
        PC_Out <= 32'b0;
        PC_Plus_4_Out <= 32'b0;
        RD1_Out <= 32'b0;
        RD2_Out <= 32'b0;
        ImmExt_Out <= 32'b0;
        Instr_Out <= 32'b0;
        WA_Out <= 5'b0;
        ALUControl_Out <= 4'b0;
        Width_Out <= 2'b0;
        ResultSrc_Out <= 2'b0;
        RegWrite_Out <= 1'b0;
        ALUSrc_Out <= 1'b0;
        MemWrite_Out <= 1'b0;
        Branch_Out <= 1'b0;
        Jump_Out <= 1'b0;
        Funct3_Out <= 3'b0;
        Predicted_Taken_Out <= 1'b0;
    end

    else
    begin
        PC_Out <= PC_In;
        PC_Plus_4_Out <= PC_Plus_4_In;
        RD1_Out <= RD1_In;
        RD2_Out <= RD2_In;
        ImmExt_Out <= ImmExt_In;
        Instr_Out <= Instr_In;
        WA_Out <= WA_In;
        ALUControl_Out <= ALUControl_In;
        Width_Out <= Instr_In[13:12];
        ResultSrc_Out <= ResultSrc_In;
        RegWrite_Out <= RegWrite_In;
        ALUSrc_Out <= ALUSrc_In;
        MemWrite_Out <= MemWrite_In;
        Branch_Out <= Branch_In;
        Jump_Out <= Jump_In;
        Funct3_Out <= Instr_In[14:12];
        Predicted_Taken_Out <= Predicted_Taken_In;
    end
end

endmodule