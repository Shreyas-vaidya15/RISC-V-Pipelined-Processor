module EX_MEM_reg
(
    input clk, reset, interrupt_taken,
    input [31:0] PC_Plus_4_In, ALUResult_In, RD2_In,
    input [4:0] WA_In,
    input [2:0] Funct3_In,
    input [1:0] Width_In, ResultSrc_In,
    input RegWrite_In, MemWrite_In,
    output reg [31:0] PC_Plus_4_Out, ALUResult_Out, RD2_Out,
    output reg [4:0] WA_Out,
    output reg [2:0] Funct3_Out,
    output reg [1:0] Width_Out, ResultSrc_Out,
    output reg RegWrite_Out, MemWrite_Out
);

always @(posedge clk or posedge reset)
begin

    if (reset | interrupt_taken)
    begin
        PC_Plus_4_Out <= 32'b0;
        ALUResult_Out <= 32'b0;
        RD2_Out <= 32'b0;
        WA_Out <= 5'b0;
        Funct3_Out <= 3'b0;
        Width_Out <= 2'b0;
        ResultSrc_Out <= 2'b0;
        RegWrite_Out <= 1'b0;
        MemWrite_Out <= 1'b0;
    end

    else
    begin
        PC_Plus_4_Out <= PC_Plus_4_In;
        ALUResult_Out <= ALUResult_In;
        RD2_Out <= RD2_In;
        WA_Out <= WA_In;
        Width_Out <= Width_In;
        ResultSrc_Out <= ResultSrc_In;
        RegWrite_Out <= RegWrite_In;
        MemWrite_Out <= MemWrite_In;
        Funct3_Out <= Funct3_In;
    end
    
end

endmodule