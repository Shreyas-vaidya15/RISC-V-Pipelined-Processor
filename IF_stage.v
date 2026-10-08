module IF_stage #(parameter DEPTH = 256)
(
input clk, reset, Stall, EX_Override, Mret_taken, interrupt_taken, exception_taken,
input [31:0] EX_RedirectPC, mepc, pc_mtvec_mcause,
output [31:0] PC, PCPlus4, Instr,
output Predicted_Taken,
output instruction_access_fault
);

localparam [31:0] NOP = 32'h00000013;   // addi x0, x0, 0

wire [31:0] PC_Next, ImmExt, PC_Predict_Target;
wire [31:0] Instr_raw;   // what the instruction memory actually returned (X / garbage if the PC is out of range)

// Out-of-range fetch: flagged here, carried to ID by IF_ID_reg.
instruction_access_fault #(.DEPTH(DEPTH)) instruction_access_fault_inst
(
    .PC_IF(PC),
    .instruction_access_fault(instruction_access_fault)
);

// Swap in a nop BEFORE the instruction splits into the predictor and the output port,
// so both of them only ever see a clean instruction.
assign Instr = instruction_access_fault ? NOP : Instr_raw;

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
    .mepc(mepc),
    .pc_mtvec_mcause(pc_mtvec_mcause),
    .EX_Override(EX_Override),
    .Mret_taken(Mret_taken),
    .interrupt_taken(interrupt_taken),
    .Predicted_Taken(Predicted_Taken),
    .exception_taken(exception_taken)
);

pc pc_inst(
    .PC(PC),
    .PCNext(PC_Next),
    .pc_mtvec_mcause(pc_mtvec_mcause),
    .clk(clk),
    .reset(reset),
    .Stall(Stall),
    .interrupt_taken(interrupt_taken),
    .exception_taken(exception_taken)
);

inst_memory #(.DEPTH(DEPTH)) instruction_memory_inst(
    .addr(PC),
    .data(Instr_raw)
);

endmodule