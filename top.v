module top
(
  input clk, reset, interrupt_keyboard, interrupt_disk
);

// ---- IF stage outputs → IF_ID_reg ----
wire [31:0] PC_IF, PCPlus4_IF, Instr_IF;
wire Predicted_Taken_IF;

// ---- IF_ID_reg outputs → ID_stage / ID_EX_reg ----
wire [31:0] PC_ID, PCPlus4_ID, Instr_ID;
wire Predicted_Taken_ID;
wire instruction_access_fault_IF, instruction_access_fault_ID;   // out-of-range fetch: flagged in IF, carried to ID by IF_ID_reg

// ---- ID_stage outputs → ID_EX_reg ----
wire [31:0] RD1_ID, RD2_ID, ImmExt_ID;
wire [4:0] WA_ID;
wire [3:0] ALUControl_ID;
wire [1:0] ResultSrc_ID;
wire Jump_ID, Branch_ID, MemWrite_ID, RegWrite_ID, ALUSrc_ID, Mret_taken_ID, IsCSR_ID;
wire Illegal_opcode_ID;   // decoder says the instruction in ID has an unknown opcode
wire Illegal_System_Imm_ID;   // SYSTEM opcode, funct3 = 000, but imm is not ecall/ebreak/mret
wire Ecall_ID, Ebreak_ID;     // ecall (cause 11) / ebreak (cause 3) in ID
wire illegal_funct7_ID;   // legal opcode, but illegal funct7 field
wire illegal_funct3_func;
wire illegal_funct3_csr;
wire illegal_csr_address_ID;   // CSR instruction with address outside 0-5
wire illegal_funct3_ID;
wire IsLoad_ID, IsLoad_EX;   // instruction is a load (needed in EX for the misaligned check, and later for AHB)
assign illegal_funct3_ID = illegal_funct3_func | illegal_funct3_csr;

// ---- ID_EX_reg outputs → EX_stage / EX_MEM_reg ----
wire [31:0] PC_EX, PCPlus4_EX, RD1_EX, RD2_EX, ImmExt_EX, Instr_EX;
wire [4:0] WA_EX;
wire [3:0] ALUControl_EX;
wire [2:0] Funct3_EX;
wire [1:0] Width_EX, ResultSrc_EX;
wire RegWrite_EX, ALUSrc_EX, MemWrite_EX, Branch_EX, Jump_EX, Predicted_Taken_EX, IsCSR_EX;
wire Mret_EX;   // an mret is currently sitting in EX (carried through ID_EX_reg)

// ---- EX_stage outputs → EX_MEM_reg (+ feedback to IF_stage) ----
wire [31:0] Result_EX, PCTarget_EX, EX_RedirectPC_EX;
wire IsJalr_EX, EX_Override_EX, Actual_Taken_EX;

// ---- EX_MEM_reg outputs → MEM_stage / MEM_WB_reg ----
wire [31:0] PCPlus4_MEM, ALUResult_MEM, RD2_MEM, csr_read_val_MEM;
wire [4:0] WA_MEM;
wire [2:0] Funct3_MEM;
wire [1:0] Width_MEM, ResultSrc_MEM;
wire RegWrite_MEM, MemWrite_MEM;

// ---- MEM_stage output → MEM_WB_reg ----
wire [31:0] ReadData_MEM;

// ---- MEM_WB_reg outputs → result_mux / id_stage feedback ----
wire [31:0] PCPlus4_WB, ALUResult_WB, ReadData_WB, csr_read_val_WB;
wire [4:0] WA_WB;
wire [1:0] ResultSrc_WB;
wire RegWrite_WB;

// ---- result_mux output → id_stage write-back (also doubles as MEM/WB forwarding candidate) ----
wire [31:0] Result_WB;

// ---- raw-field slice needed before ID_EX_reg ----
assign WA_ID = Instr_ID[11:7];

// ============ FORWARDING WIRES ============

wire [31:0] EX_MEM_Candidate;
assign EX_MEM_Candidate = (ResultSrc_MEM == 2'b10) ? PCPlus4_MEM :
                           (ResultSrc_MEM == 2'b11) ? csr_read_val_MEM :
                           ALUResult_MEM;

wire [1:0] ForwardA, ForwardB;
wire [31:0] ForwardedRD1, ForwardedRD2;

wire Stall_raw;
wire Stall = Stall_raw & ~Mret_taken_ID;

// ============ INTERRUPT / TRAP WIRES ============

wire [31:0] mepc_val, mcause_val, mtvec_val, pc_mtvec_mcause_val;
wire mie_val;
wire mpie_val;                           // previous mie: saved on trap entry, restored into mie by mret
wire [1:0] current_priority_val, previous_priority_val;
wire pending_keyboard, pending_disk;
wire [1:0] interrupt_ID;                 // 00 = nobody asking, 01 = keyboard, 10 = disk
wire interrupt_taken;                    // source-agnostic: the CPU only needs "trap or don't"
wire interrupt_keyboard_taken, interrupt_disk_taken;   // per-source: used only to clear that source's pending bit

// EX holds a bubble (flush/stall inserted an all-zero instruction). A real instruction is never all zeros.
// Taking a trap now would save a bogus PC (0) into mepc.
wire EX_is_bubble = (Instr_EX == 32'b0);

// Someone is actually asking (ID != 00) AND its level is at least the level currently running.
wire priority_ok = (interrupt_ID != 2'b00) && (interrupt_ID >= current_priority_val);

// Accept a trap only if: interrupts on, priority rule passes,
// and EX holds neither a bubble nor an mret (mret in EX = return address already redirected; a trap now would overwrite mepc with the mret's own PC).
assign interrupt_taken = mie_val & priority_ok & ~EX_is_bubble & ~Mret_EX;

// Per-source clears: only the source that was actually served loses its pending bit.
assign interrupt_disk_taken     = interrupt_taken & (interrupt_ID == 2'b10);
assign interrupt_keyboard_taken = interrupt_taken & (interrupt_ID == 2'b01);

// ---- Illegal funct3 / funct7 detection (instruction in ID) ----
illegal_function illegal_function_inst
(
    .funct7(Instr_ID[31:25]),
    .op(Instr_ID[6:0]),
    .funct3(Instr_ID[14:12]),
    .illegal_funct7(illegal_funct7_ID),
    .illegal_funct3(illegal_funct3_func)
);

// Any of the three illegal-instruction flags raised in ID.
wire illegal_instr_ID = Illegal_opcode_ID | illegal_funct7_ID | illegal_funct3_ID | illegal_csr_address_ID | Illegal_System_Imm_ID;

// ---- Exception (illegal opcode / funct7 / funct3, detected in ID) ----
// An interrupt always wins if both happen in the same cycle.
// ~EX_Override_EX: an illegal-looking instruction behind a mispredicted branch / jump is on the wrong path and gets flushed, so it must not trap.
// ---- Misaligned load/store (detected in EX, from the ALU address) ----
wire misalign_detect, misalign_is_store;

misaligned_detect misaligned_detect_inst
(
    .IsLoad(IsLoad_EX),
    .MemWrite(MemWrite_EX),
    .funct3(Funct3_EX),
    .addr(Result_EX),
    .misaligned(misalign_detect),
    .misaligned_store(misalign_is_store)
);

// Exception raised from EX: the misaligned instruction itself is squashed (like an interrupt).
// An interrupt in the same cycle wins; the access re-faults after mret.
// Instruction-address-misaligned (cause 0): a taken branch / jal / jalr whose target has bit 1 set.
wire fetch_misalign_EX;

instruction_address_misalign instruction_address_misalign_inst
(
    .Actual_Taken(Actual_Taken_EX),
    .Branch(Branch_EX),
    .Jump(Jump_EX),
    .IsJalr(IsJalr_EX),
    .ALUResult_b1(Result_EX[1]),
    .PCTarget_b1(PCTarget_EX[1]),
    .instruction_address_misalign(fetch_misalign_EX)
);

// Load/store access fault (cause 5 / 7): address outside the data memory.
// DATA_DEPTH is in WORDS and must match data_memory's DEPTH (default 64 = 256 bytes).
localparam DATA_DEPTH = 64;
wire ls_access_fault_EX;

load_store_access_fault #(.DEPTH(DATA_DEPTH)) load_store_access_fault_inst
(
    .IsLoad(IsLoad_EX),
    .MemWrite(MemWrite_EX),
    .ALUResult(Result_EX),
    .load_store_access_fault(ls_access_fault_EX)
);

wire exception_taken_EX = (misalign_detect | fetch_misalign_EX | ls_access_fault_EX) & ~interrupt_taken;

// Exception raised from ID: the instruction in EX is older and must finish.
// ~exception_taken_EX: the EX instruction is older than the one in ID, so it traps first.
// ecall / ebreak are raised from ID exactly like an illegal instruction (same gating), only the cause differs.
// instruction_access_fault_ID: the fetch address was outside the instruction memory (IF swapped in a nop, so the other flags are all 0).
wire id_exception_pending = illegal_instr_ID | Ecall_ID | Ebreak_ID | instruction_access_fault_ID;
wire exception_taken_ID = id_exception_pending & ~interrupt_taken & ~EX_Override_EX & ~exception_taken_EX;

// Source-agnostic: used by everything that only needs "an exception happened" (PC, IF/ID, ID/EX, CSRs).
wire exception_taken = exception_taken_ID | exception_taken_EX;

// mepc for an exception: the PC of the faulting instruction (EX for misaligned, ID for illegal).
wire [31:0] exception_mepc = exception_taken_EX ? PC_EX : PC_ID;

// Cause code used for BOTH the trap vector (same cycle) and the mcause register.
// Interrupt taken -> interrupt cause (bit 31 = 1). Otherwise -> exception cause (bit 31 = 0): 2 = illegal instruction.
// Exception cause: 6 = store address misaligned, 4 = load address misaligned, 2 = illegal instruction.
// ID-sourced cause: 11 = ecall, 3 = ebreak, otherwise 2 = illegal instruction (the flags are mutually exclusive).
// Must match exception_cause_next in mcause.v.
wire [31:0] id_cause_val = instruction_access_fault_ID ? 32'd1  :
                           Ecall_ID                    ? 32'd11 :
                           Ebreak_ID                   ? 32'd3  :
                                                         32'd2;
wire [31:0] exception_cause_val = misalign_detect     ? (misalign_is_store ? 32'd6 : 32'd4) :
                                  ls_access_fault_EX  ? (IsLoad_EX ? 32'd5 : 32'd7) :
                                  fetch_misalign_EX   ? 32'd0 :
                                                        id_cause_val;

wire [31:0] mcause_next = interrupt_taken ? ((interrupt_ID == 2'd2) ? {1'b1, 31'd27} : {1'b1, 31'd7})
                                          : exception_cause_val;

// A decode-stage mret sitting behind a mispredicted branch is on the wrong path and will be flushed:
// it must not restore mie / mpie / current_priority.
wire Mret_valid_ID = Mret_taken_ID & ~EX_Override_EX & ~exception_taken_EX;

// ============ CSR WIRES ============

wire mepc_write_en, mie_write_en, mcause_write_en, current_priority_write_en, previous_priority_write_en, mpie_write_en;
wire [31:0] csr_wdata;
wire [31:0] csr_read_val_EX;

// ============ INSTANTIATIONS ============

IF_stage IF_stage_inst
(
    .clk(clk),
    .reset(reset),
    .Stall(Stall),
    .EX_Override(EX_Override_EX),
    .Mret_taken(Mret_taken_ID),
    .interrupt_taken(interrupt_taken),
    .exception_taken(exception_taken),
    .EX_RedirectPC(EX_RedirectPC_EX),
    .mepc(mepc_val),
    .pc_mtvec_mcause(pc_mtvec_mcause_val),
    .PC(PC_IF),
    .PCPlus4(PCPlus4_IF),
    .Instr(Instr_IF),
    .Predicted_Taken(Predicted_Taken_IF),
    .instruction_access_fault(instruction_access_fault_IF)
);

IF_ID_reg IF_ID_reg_inst
(
    .clk(clk),
    .reset(reset),
    .Flush(EX_Override_EX),
    .Stall(Stall),
    .Mret_taken(Mret_taken_ID),
    .interrupt_taken(interrupt_taken),
    .exception_taken(exception_taken),
    .Predicted_Taken_In(Predicted_Taken_IF),
    .Instr_In(Instr_IF),
    .PC_In(PC_IF),
    .PC_Plus_4_In(PCPlus4_IF),
    .Instr_Out(Instr_ID),
    .PC_Out(PC_ID),
    .PC_Plus_4_Out(PCPlus4_ID),
    .Predicted_Taken_Out(Predicted_Taken_ID),
    .instruction_access_fault_In(instruction_access_fault_IF),
    .instruction_access_fault_Out(instruction_access_fault_ID)
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
    .IsCSR(IsCSR_ID),
    .IsLoad(IsLoad_ID),
    .Illegal_opcode(Illegal_opcode_ID),
    .Illegal_System_Imm(Illegal_System_Imm_ID),
    .Ecall(Ecall_ID),
    .Ebreak(Ebreak_ID),
    .illegal_funct3_csr(illegal_funct3_csr),
    .illegal_csr_address(illegal_csr_address_ID),
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
    .exception_taken(exception_taken),
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
    .IsCSR_In(IsCSR_ID),
    .Mret_taken_In(Mret_taken_ID),
    .IsLoad_In(IsLoad_ID),
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
    .Predicted_Taken_Out(Predicted_Taken_EX),
    .IsCSR_Out(IsCSR_EX),
    .Mret_taken_Out(Mret_EX),
    .IsLoad_Out(IsLoad_EX)
);

stall_unit stall_unit_inst
(
    .ID_EX_opcode(Instr_EX[6:0]),
    .IF_ID_rs1(Instr_ID[19:15]),
    .IF_ID_rs2(Instr_ID[24:20]),
    .ID_EX_WA(WA_EX),
    .Stall(Stall_raw)
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
    .IsCSR(IsCSR_EX),
    .ALUControl(ALUControl_EX),
    .ImmExt(ImmExt_EX),
    .RD1(ForwardedRD1),
    .RD2(ForwardedRD2),
    .PC(PC_EX),
    .Instr(Instr_EX),
    .PC_Plus_4(PCPlus4_EX),
    .csr_read_val(csr_read_val_EX),
    .IsJalr(IsJalr_EX),
    .EX_Override(EX_Override_EX),
    .Actual_Taken(Actual_Taken_EX),
    .Result(Result_EX),
    .PCTarget(PCTarget_EX),
    .EX_RedirectPC(EX_RedirectPC_EX)
);

// EX_MEM_reg flushes on an interrupt or an EX-stage exception (the instruction in EX is squashed), NEVER on an ID-stage exception:
// for an exception detected in ID, the instruction in EX is older and must finish.
EX_MEM_reg EX_MEM_reg_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_taken(interrupt_taken),
    .exception_taken_EX(exception_taken_EX),
    .PC_Plus_4_In(PCPlus4_EX),
    .ALUResult_In(Result_EX),
    .RD2_In(ForwardedRD2),
    .csr_read_val_In(csr_read_val_EX),
    .WA_In(WA_EX),
    .Funct3_In(Funct3_EX),
    .Width_In(Width_EX),
    .ResultSrc_In(ResultSrc_EX),
    .RegWrite_In(RegWrite_EX),
    .MemWrite_In(MemWrite_EX),
    .PC_Plus_4_Out(PCPlus4_MEM),
    .ALUResult_Out(ALUResult_MEM),
    .RD2_Out(RD2_MEM),
    .csr_read_val_Out(csr_read_val_MEM),
    .WA_Out(WA_MEM),
    .Funct3_Out(Funct3_MEM),
    .Width_Out(Width_MEM),
    .ResultSrc_Out(ResultSrc_MEM),
    .RegWrite_Out(RegWrite_MEM),
    .MemWrite_Out(MemWrite_MEM)
);

MEM_stage #(.DEPTH(DATA_DEPTH)) MEM_stage_inst
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
    .csr_read_val_In(csr_read_val_MEM),
    .WA_In(WA_MEM),
    .ResultSrc_In(ResultSrc_MEM),
    .RegWrite_In(RegWrite_MEM),
    .PC_Plus_4_Out(PCPlus4_WB),
    .ALUResult_Out(ALUResult_WB),
    .ReadData_Out(ReadData_WB),
    .csr_read_val_Out(csr_read_val_WB),
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
    .csr_read_val(csr_read_val_WB),
    .ResultSrc(ResultSrc_WB)
);

// ---- Interrupt pending latches (each cleared only by its own source being taken) ----

interrupt_latch keyboard_latch_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_in(interrupt_keyboard),
    .interrupt_taken(interrupt_keyboard_taken),
    .interrupt_pending(pending_keyboard)
);

interrupt_latch disk_latch_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_in(interrupt_disk),
    .interrupt_taken(interrupt_disk_taken),
    .interrupt_pending(pending_disk)
);

// ---- Who is asking (highest pending level wins the tie-break) ----

interrupt_priority_encoder interrupt_priority_encoder_inst
(
    .pending_keyboard(pending_keyboard),
    .pending_disk(pending_disk),
    .interrupt_ID(interrupt_ID)
);

// ---- Priority level tracking (interrupts only; exceptions do not touch these yet) ----

current_priority current_priority_inst
(
    .interrupt_ID(interrupt_ID),
    .csr_wdata(csr_wdata[1:0]),
    .previous_priority(previous_priority_val),
    .interrupt_taken(interrupt_taken),
    .clk(clk),
    .reset(reset),
    .current_priority_write_en(current_priority_write_en),
    .mret_taken(Mret_valid_ID),
    .current_priority(current_priority_val)
);

previous_priority previous_priority_inst
(
    .current_priority(current_priority_val),
    .csr_wdata(csr_wdata[1:0]),
    .clk(clk),
    .reset(reset),
    .interrupt_taken(interrupt_taken),
    .previous_priority_write_en(previous_priority_write_en),
    .exception_taken(exception_taken),
    .current_priority_write_en(current_priority_write_en),
    .previous_priority(previous_priority_val)
);

// ---- CSR / trap logic ----

mepc mepc_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_taken(interrupt_taken),
    .exception_taken(exception_taken),
    .mepc_write_en(mepc_write_en),
    .csr_wdata(csr_wdata),
    .EX_MEPC_IN(PC_EX),
    .ID_MEPC_IN(exception_mepc),
    .MEPC_OUT(mepc_val)
);

mcause mcause_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_ID(interrupt_ID),
    .interrupt_taken(interrupt_taken),
    .exception_taken(exception_taken),
    .misaligned(misalign_detect),
    .misaligned_store(misalign_is_store),
    .Ecall(Ecall_ID),
    .Ebreak(Ebreak_ID),
    .instruction_address_misalign(fetch_misalign_EX),
    .instruction_access_fault(instruction_access_fault_ID),
    .load_store_access_fault(ls_access_fault_EX),
    .IsLoad(IsLoad_EX),
    .mcause_write_en(mcause_write_en),
    .csr_wdata(csr_wdata),
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

// mie: cleared on ANY trap (interrupt or exception), restored from mpie by a valid mret
mie mie_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_taken(interrupt_taken),
    .exception_taken(exception_taken),
    .mret_taken(Mret_valid_ID),
    .mie_write_en(mie_write_en),
    .csr_wdata_b0(csr_wdata[0]),
    .mpie_out(mpie_val),
    .mie_out(mie_val)
);

// mpie: saves mie on ANY trap, set to 1 by a valid mret
mpie mpie_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_taken(interrupt_taken),
    .exception_taken(exception_taken),
    .mret_taken(Mret_valid_ID),
    .mpie_write_en(mpie_write_en),
    .mie_out(mie_val),
    .csr_wdata_b0(csr_wdata[0]),
    .mie_write_en(mie_write_en),
    .mpie_out(mpie_val)
);

csr_addr_decoder csr_addr_decoder_inst
(
    .csr_addr(Instr_EX[31:20]),
    .IsCSR(IsCSR_EX),
    .mepc_write_en(mepc_write_en),
    .mie_write_en(mie_write_en),
    .mcause_write_en(mcause_write_en),
    .current_priority_write_en(current_priority_write_en),
    .previous_priority_write_en(previous_priority_write_en),
    .mpie_write_en(mpie_write_en)
);

csr_write_data csr_write_data_inst
(
    .ALUResult(Result_EX),
    .ImmExt(ImmExt_EX),
    .rs1(ForwardedRD1),
    .funct3(Instr_EX[14:12]),
    .csr_wdata(csr_wdata)
);

csr_read_data csr_read_data_inst
(
    .mepc_write_en(mepc_write_en),
    .mie_write_en(mie_write_en),
    .mcause_write_en(mcause_write_en),
    .current_priority_write_en(current_priority_write_en),
    .previous_priority_write_en(previous_priority_write_en),
    .mpie_write_en(mpie_write_en),
    .mie_val(mie_val),
    .mpie_val(mpie_val),
    .mepc_val(mepc_val),
    .mcause_val(mcause_val),
    .current_priority(current_priority_val),
    .previous_priority(previous_priority_val),
    .csr_read_val(csr_read_val_EX)
);

endmodule