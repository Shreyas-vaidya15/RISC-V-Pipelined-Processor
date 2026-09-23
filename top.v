module top
(
  input clk, reset, interrupt
);

// ---- IF stage outputs → IF_ID_reg ----
wire [31:0] PC_IF, PCPlus4_IF, Instr_IF;
wire Predicted_Taken_IF;

// ---- IF_ID_reg outputs → ID_stage / ID_EX_reg ----
wire [31:0] PC_ID, PCPlus4_ID, Instr_ID;
wire Predicted_Taken_ID;

// ---- ID_stage outputs → ID_EX_reg ----
wire [31:0] RD1_ID, RD2_ID, ImmExt_ID;
wire [4:0] WA_ID;
wire [3:0] ALUControl_ID;
wire [1:0] ResultSrc_ID;
wire Jump_ID, Branch_ID, MemWrite_ID, RegWrite_ID, ALUSrc_ID, Mret_taken_ID;

// ---- ID_EX_reg outputs → EX_stage / EX_MEM_reg ----
wire [31:0] PC_EX, PCPlus4_EX, RD1_EX, RD2_EX, ImmExt_EX, Instr_EX;
wire [4:0] WA_EX;
wire [3:0] ALUControl_EX;
wire [2:0] Funct3_EX;
wire [1:0] Width_EX, ResultSrc_EX;
wire RegWrite_EX, ALUSrc_EX, MemWrite_EX, Branch_EX, Jump_EX, Predicted_Taken_EX;

// ---- EX_stage outputs → EX_MEM_reg (+ feedback to IF_stage) ----
wire [31:0] Result_EX, PCTarget_EX, EX_RedirectPC_EX;
wire IsJalr_EX, EX_Override_EX;

// ---- EX_MEM_reg outputs → MEM_stage / MEM_WB_reg ----
wire [31:0] PCPlus4_MEM, ALUResult_MEM, RD2_MEM;
wire [4:0] WA_MEM;
wire [2:0] Funct3_MEM;
wire [1:0] Width_MEM, ResultSrc_MEM;
wire RegWrite_MEM, MemWrite_MEM;

// ---- MEM_stage output → MEM_WB_reg ----
wire [31:0] ReadData_MEM;

// ---- MEM_WB_reg outputs → result_mux / id_stage feedback ----
wire [31:0] PCPlus4_WB, ALUResult_WB, ReadData_WB;
wire [4:0] WA_WB;
wire [1:0] ResultSrc_WB;
wire RegWrite_WB;

// ---- result_mux output → id_stage write-back (also doubles as MEM/WB forwarding candidate) ----
wire [31:0] Result_WB;

// ---- raw-field slice needed before ID_EX_reg ----
assign WA_ID = Instr_ID[11:7];

// ============ FORWARDING WIRES ============

wire [31:0] EX_MEM_Candidate;
assign EX_MEM_Candidate = (ResultSrc_MEM == 2'b10) ? PCPlus4_MEM : ALUResult_MEM;

wire [1:0] ForwardA, ForwardB;
wire [31:0] ForwardedRD1, ForwardedRD2;

wire Stall;

// ============ INTERRUPT / TRAP WIRES ============

wire [31:0] mepc_val, mcause_val, mtvec_val, pc_mtvec_mcause_val;
wire mie_val;
wire interrupt_taken;

assign interrupt_taken = interrupt & mie_val;

// Combinational mirror of the exception code mcause.v will latch.
// Used ONLY for the trap-target math so the redirect doesn't lag
// one cycle behind the registered mcause_val (same-cycle race fix).
wire [31:0] mcause_next = {1'b1, 31'd7};

// ============ INSTANTIATIONS ============

IF_stage IF_stage_inst
(
    .clk(clk),
    .reset(reset),
    .Stall(Stall),
    .EX_Override(EX_Override_EX),
    .Mret_taken(Mret_taken_ID),
    .interrupt_taken(interrupt_taken),
    .EX_RedirectPC(EX_RedirectPC_EX),
    .mepc(mepc_val),
    .pc_mtvec_mcause(pc_mtvec_mcause_val),
    .PC(PC_IF),
    .PCPlus4(PCPlus4_IF),
    .Instr(Instr_IF),
    .Predicted_Taken(Predicted_Taken_IF)
);

IF_ID_reg IF_ID_reg_inst
(
    .clk(clk),
    .reset(reset),
    .Flush(EX_Override_EX),
    .Stall(Stall),
    .Mret_taken(Mret_taken_ID),
    .interrupt_taken(interrupt_taken),
    .Predicted_Taken_In(Predicted_Taken_IF),
    .Instr_In(Instr_IF),
    .PC_In(PC_IF),
    .PC_Plus_4_In(PCPlus4_IF),
    .Instr_Out(Instr_ID),
    .PC_Out(PC_ID),
    .PC_Plus_4_Out(PCPlus4_ID),
    .Predicted_Taken_Out(Predicted_Taken_ID)
);

ID_stage ID_stage_inst
(
    .clk(clk),
    .we(RegWrite_WB),
    .wa(WA_WB),
    .wd(Result_WB),
    .Instr_In(Instr_ID),
    .Jump(Jump_ID),
    .Branch(Branch_ID),
    .MemWrite(MemWrite_ID),
    .RegWrite(RegWrite_ID),
    .ALUSrc(ALUSrc_ID),
    .Mret_taken(Mret_taken_ID),
    .ResultSrc(ResultSrc_ID),
    .ALUControl(ALUControl_ID),
    .rd1(RD1_ID),
    .rd2(RD2_ID),
    .ImmExt(ImmExt_ID)
);

ID_EX_reg ID_EX_reg_inst
(
    .clk(clk),
    .reset(reset),
    .Flush(EX_Override_EX),
    .Stall(Stall),
    .interrupt_taken(interrupt_taken),
    .PC_In(PC_ID),
    .PC_Plus_4_In(PCPlus4_ID),
    .RD1_In(RD1_ID),
    .RD2_In(RD2_ID),
    .ImmExt_In(ImmExt_ID),
    .Instr_In(Instr_ID),
    .WA_In(WA_ID),
    .ALUControl_In(ALUControl_ID),
    .ResultSrc_In(ResultSrc_ID),
    .RegWrite_In(RegWrite_ID),
    .ALUSrc_In(ALUSrc_ID),
    .MemWrite_In(MemWrite_ID),
    .Branch_In(Branch_ID),
    .Jump_In(Jump_ID),
    .Predicted_Taken_In(Predicted_Taken_ID),
    .PC_Out(PC_EX),
    .PC_Plus_4_Out(PCPlus4_EX),
    .RD1_Out(RD1_EX),
    .RD2_Out(RD2_EX),
    .ImmExt_Out(ImmExt_EX),
    .Instr_Out(Instr_EX),
    .WA_Out(WA_EX),
    .ALUControl_Out(ALUControl_EX),
    .Funct3_Out(Funct3_EX),
    .Width_Out(Width_EX),
    .ResultSrc_Out(ResultSrc_EX),
    .RegWrite_Out(RegWrite_EX),
    .ALUSrc_Out(ALUSrc_EX),
    .MemWrite_Out(MemWrite_EX),
    .Branch_Out(Branch_EX),
    .Jump_Out(Jump_EX),
    .Predicted_Taken_Out(Predicted_Taken_EX)
);

stall_unit stall_unit_inst
(
    .ID_EX_opcode(Instr_EX[6:0]),
    .IF_ID_rs1(Instr_ID[19:15]),
    .IF_ID_rs2(Instr_ID[24:20]),
    .ID_EX_WA(WA_EX),
    .Stall(Stall)
);

forwarding_unit forwarding_unit_inst
(
    .rs1(Instr_EX[19:15]),
    .rs2(Instr_EX[24:20]),
    .EX_MEM_WA(WA_MEM),
    .MEM_WB_WA(WA_WB),
    .EX_MEM_RegWrite(RegWrite_MEM),
    .MEM_WB_RegWrite(RegWrite_WB),
    .ForwardA(ForwardA),
    .ForwardB(ForwardB)
);

forward_mux forward_mux_A
(
    .regfile_rs(RD1_EX),
    .EX_MEM_rs(EX_MEM_Candidate),
    .MEM_WB_rs(Result_WB),
    .forward_sel(ForwardA),
    .final_rs(ForwardedRD1)
);

forward_mux forward_mux_B
(
    .regfile_rs(RD2_EX),
    .EX_MEM_rs(EX_MEM_Candidate),
    .MEM_WB_rs(Result_WB),
    .forward_sel(ForwardB),
    .final_rs(ForwardedRD2)
);

EX_stage EX_stage_inst
(
    .ALUSrc(ALUSrc_EX),
    .Branch(Branch_EX),
    .Jump(Jump_EX),
    .Predicted_Taken(Predicted_Taken_EX),
    .ALUControl(ALUControl_EX),
    .ImmExt(ImmExt_EX),
    .RD1(ForwardedRD1),
    .RD2(ForwardedRD2),
    .PC(PC_EX),
    .Instr(Instr_EX),
    .PC_Plus_4(PCPlus4_EX),
    .IsJalr(IsJalr_EX),
    .EX_Override(EX_Override_EX),
    .Result(Result_EX),
    .PCTarget(PCTarget_EX),
    .EX_RedirectPC(EX_RedirectPC_EX)
);

EX_MEM_reg EX_MEM_reg_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_taken(interrupt_taken),
    .PC_Plus_4_In(PCPlus4_EX),
    .ALUResult_In(Result_EX),
    .RD2_In(ForwardedRD2),
    .WA_In(WA_EX),
    .Funct3_In(Funct3_EX),
    .Width_In(Width_EX),
    .ResultSrc_In(ResultSrc_EX),
    .RegWrite_In(RegWrite_EX),
    .MemWrite_In(MemWrite_EX),
    .PC_Plus_4_Out(PCPlus4_MEM),
    .ALUResult_Out(ALUResult_MEM),
    .RD2_Out(RD2_MEM),
    .WA_Out(WA_MEM),
    .Funct3_Out(Funct3_MEM),
    .Width_Out(Width_MEM),
    .ResultSrc_Out(ResultSrc_MEM),
    .RegWrite_Out(RegWrite_MEM),
    .MemWrite_Out(MemWrite_MEM)
);

MEM_stage MEM_stage_inst
(
    .clk(clk),
    .MemWrite(MemWrite_MEM),
    .Width(Width_MEM),
    .Funct3(Funct3_MEM),
    .RD2(RD2_MEM),
    .ALUResult(ALUResult_MEM),
    .ReadData(ReadData_MEM)
);

MEM_WB_reg MEM_WB_reg_inst
(
    .clk(clk),
    .reset(reset),
    .PC_Plus_4_In(PCPlus4_MEM),
    .ALUResult_In(ALUResult_MEM),
    .ReadData_In(ReadData_MEM),
    .WA_In(WA_MEM),
    .ResultSrc_In(ResultSrc_MEM),
    .RegWrite_In(RegWrite_MEM),
    .PC_Plus_4_Out(PCPlus4_WB),
    .ALUResult_Out(ALUResult_WB),
    .ReadData_Out(ReadData_WB),
    .WA_Out(WA_WB),
    .ResultSrc_Out(ResultSrc_WB),
    .RegWrite_Out(RegWrite_WB)
);

result_mux result_mux_inst
(
    .Result(Result_WB),
    .ALUResult(ALUResult_WB),
    .ReadData(ReadData_WB),
    .PC_Plus_4(PCPlus4_WB),
    .ResultSrc(ResultSrc_WB)
);

// ---- CSR / trap logic ----

mepc mepc_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_taken(interrupt_taken),
    .EX_MEPC_IN(PC_EX),
    .MEPC_OUT(mepc_val)
);

mcause mcause_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_taken(interrupt_taken),
    .mcause(mcause_val)
);

mtvec mtvec_inst
(
    .mtvec(mtvec_val)
);

pc_mtvec_mcause pc_mtvec_mcause_inst
(
    .mtvec(mtvec_val),
    .mcause(mcause_next),
    .pc_mtvec_mcause(pc_mtvec_mcause_val)
);

mie mie_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_taken(interrupt_taken),
    .mret_taken(Mret_taken_ID),
    .mie_out(mie_val)
);

endmodule