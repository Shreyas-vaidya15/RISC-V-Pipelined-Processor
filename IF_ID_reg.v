module IF_ID_reg
(
    input clk, reset, Flush, Stall, Predicted_Taken_In, Mret_taken, interrupt_taken, exception_taken, instruction_access_fault_In,
    input [31:0] Instr_In, PC_In, PC_Plus_4_In,
    output reg [31:0] Instr_Out, PC_Out, PC_Plus_4_Out,
    output reg Predicted_Taken_Out, instruction_access_fault_Out
);

always@(posedge clk or posedge reset)
begin

if(reset | Flush | Mret_taken | interrupt_taken | exception_taken)
begin
Instr_Out <= 32'b0;
PC_Out <= 32'b0;
PC_Plus_4_Out <= 32'b0;
Predicted_Taken_Out <= 1'b0;
instruction_access_fault_Out <= 1'b0;
end

else if(Stall)
begin
Instr_Out <= Instr_Out;
PC_Out <= PC_Out;
PC_Plus_4_Out <= PC_Plus_4_Out;
Predicted_Taken_Out <= Predicted_Taken_Out;
instruction_access_fault_Out <= instruction_access_fault_Out;
end

else
begin
Instr_Out <= Instr_In;
PC_Out <= PC_In;
PC_Plus_4_Out <= PC_Plus_4_In;
Predicted_Taken_Out <= Predicted_Taken_In;
instruction_access_fault_Out <= instruction_access_fault_In;
end

end

endmodule