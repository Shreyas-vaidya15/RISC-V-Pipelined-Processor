module MEM_WB_reg
(
    input clk, reset,
    input [31:0] PC_Plus_4_In, ALUResult_In, ReadData_In, csr_read_val_In,
    input [4:0] WA_In,
    input [1:0] ResultSrc_In,
    input RegWrite_In,
    output reg [31:0] PC_Plus_4_Out, ALUResult_Out, ReadData_Out, csr_read_val_Out,
    output reg [4:0] WA_Out,
    output reg [1:0] ResultSrc_Out,
    output reg RegWrite_Out
);

always @(posedge clk or posedge reset)
begin

    if (reset)
    begin
        PC_Plus_4_Out <= 32'b0;
        ALUResult_Out <= 32'b0;
        ReadData_Out <= 32'b0;
        csr_read_val_Out <= 32'b0;
        WA_Out <= 5'b0;
        ResultSrc_Out <= 2'b0;
        RegWrite_Out <= 1'b0;
    end

    else
    begin
        PC_Plus_4_Out <= PC_Plus_4_In;
        ALUResult_Out <= ALUResult_In;
        ReadData_Out <= ReadData_In;
        csr_read_val_Out <= csr_read_val_In;
        WA_Out <= WA_In;
        ResultSrc_Out <= ResultSrc_In;
        RegWrite_Out <= RegWrite_In;
    end
    
end

endmodule