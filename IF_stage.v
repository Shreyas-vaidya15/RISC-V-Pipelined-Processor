module IF_stage
(
input clk, reset, Stall, EX_Override,
input [31:0] EX_RedirectPC,
output [31:0] PC, PCPlus4, Instr,
output Predicted_Taken
);

wire [31:0] PC_Next, ImmExt, PC_Predict_Target;

assign Predicted_Taken = (Instr[31] & (Instr[6:0] == 7'b1100011));
assign ImmExt = {{20{Instr[31]}}, Instr[7], Instr[30:25], Instr[11:8], 1'b0};

pc_plus_4 pc_plus_4_inst(
    .PC(PC),
    .PCPlus4(PCPlus4)
);

pc_target pc_target_predict_inst(
    .PCTarget(PC_Predict_Target),
    .PC(PC),
    .ImmExt(ImmExt)
);

pc_mux pc_mux_inst(
    .PC_Next(PC_Next),
    .PC_Target_Predicted(PC_Predict_Target),
    .PC_Plus_4(PCPlus4),
    .EX_RedirectPC(EX_RedirectPC),
    .EX_Override(EX_Override),
    .Predicted_Taken(Predicted_Taken)
);

pc pc_inst(
    .PC(PC),
    .PCNext(PC_Next),
    .clk(clk),
    .reset(reset),
    .Stall(Stall)
);

inst_memory instruction_memory_inst(
    .addr(PC),
    .data(Instr)
);

endmodule