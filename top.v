module top
(
  input clk, reset, interrupt_keyboard, interrupt_disk,

  // ---- AHB-Lite master side (data bus) ----
  input         HREADY,
  input  [31:0] HRDATA,
  output        HWRITE,
  output [1:0]  HTRANS,
  output [2:0]  HSIZE,
  output [31:0] HADDR,
  output [31:0] HWDATA
);

// ---- IF stage outputs → IF_ID_reg ----
wire [31:0] PC_IF, PCPlus4_IF, Instr_IF;
wire Predicted_Taken_IF;

// ---- IF_ID_reg outputs → ID_stage / ID_EX_reg ----
wire [31:0] PC_ID, PCPlus4_ID, Instr_ID;
wire Predicted_Taken_ID;
wire Valid_ID, Valid_EX;   // 1 = real instruction, 0 = bubble (flush / stall / reset)
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
wire illegal_csr_address_ID;   // CSR instruction whose address is not one of the implemented CSRs
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
wire RegWrite_MEM, MemWrite_MEM, IsLoad_MEM;

// ---- (no MEM_stage module any more: the data memory is an AHB slave outside the CPU) ----

// ---- MEM_WB_reg outputs → result_mux / id_stage feedback ----
wire [31:0] PCPlus4_WB, ALUResult_WB, ReadData_WB, csr_read_val_WB, RD2_WB;   // ReadData_WB = load_extend output (HRDATA extended)
wire [4:0] WA_WB;
wire [1:0] ResultSrc_WB;
wire RegWrite_WB, IsLoad_WB, MemWrite_WB;
wire [2:0] Funct3_WB;

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
wire mie_val;                           // mstatus.MIE: global interrupt enable (master switch)
wire [31:0] mie_csr_val;                // the mie CSR (0x304): per-source enables, bit 11 = external (keyboard + disk), bit 7 = timer
wire mpie_val;                           // previous mie: saved on trap entry, restored into mie by mret
wire [1:0] current_priority_val, previous_priority_val;
wire pending_keyboard, pending_disk;
wire [1:0] interrupt_ID;                 // 00 = nobody asking, 01 = keyboard, 10 = disk
wire interrupt_taken;                    // source-agnostic: the CPU only needs "trap or don't"
wire interrupt_keyboard_taken, interrupt_disk_taken;   // per-source: used only to clear that source's pending bit

// EX holds a bubble (flush/stall inserted an all-zero instruction). A real instruction is never all zeros.
// Taking a trap now would save a bogus PC (0) into mepc.
wire EX_is_bubble = ~Valid_EX;

// Someone is actually asking (ID != 00) AND its level is strictly higher than the level currently running.
wire priority_ok = (interrupt_ID != 2'b00) && (interrupt_ID > current_priority_val);

// Accept a trap only if: interrupts on (mstatus.MIE), external interrupts enabled (mie[11]; keyboard and disk are both external), priority rule passes,
// and EX holds neither a bubble nor an mret (mret in EX = return address already redirected; a trap now would overwrite mepc with the mret's own PC).
assign interrupt_taken = mie_val & mie_csr_val[11] & priority_ok & ~EX_is_bubble & ~Mret_EX & HREADY;

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

// Any of the illegal-instruction flags raised in ID.
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

wire exception_taken_EX = (misalign_detect | fetch_misalign_EX | ls_access_fault_EX) & ~interrupt_taken & HREADY;

// Exception raised from ID: the instruction in EX is older and must finish.
// ~exception_taken_EX: the EX instruction is older than the one in ID, so it traps first.
// ecall / ebreak are raised from ID exactly like an illegal instruction (same gating), only the cause differs.
// instruction_access_fault_ID: the fetch address was outside the instruction memory (IF swapped in a nop, so the other flags are all 0).
wire id_exception_pending = illegal_instr_ID | Ecall_ID | Ebreak_ID | instruction_access_fault_ID;
wire exception_taken_ID = id_exception_pending & ~interrupt_taken & ~EX_Override_EX & ~exception_taken_EX & HREADY;

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

// Keyboard and disk are both machine external interrupts: cause 11 (interrupt bit set). The timer will be cause 7.
wire [31:0] mcause_next = interrupt_taken ? {1'b1, 31'd11}
                                          : exception_cause_val;

// mtval: extra information about the trap, in the same priority order as the cause chain above.
// bad address for load/store faults, bad jump target for cause 0, bad fetch address for cause 1, the instruction bits for illegal instruction, 0 for ecall/ebreak.
wire [31:0] mtval_next = (misalign_detect | ls_access_fault_EX) ? Result_EX :
                         fetch_misalign_EX                      ? (IsJalr_EX ? {Result_EX[31:1], 1'b0} : PCTarget_EX) :
                         instruction_access_fault_ID            ? PC_ID :
                         illegal_instr_ID                       ? Instr_ID :
                                                                  32'd0;
wire [31:0] mtval_val;

// A decode-stage mret sitting behind a mispredicted branch is on the wrong path and will be flushed:
// it must not restore mie / mpie / current_priority.
wire Mret_valid_ID = Mret_taken_ID & ~EX_Override_EX & ~exception_taken_EX & HREADY;

// ============ CSR WIRES ============

wire mepc_write_en, mie_write_en, mcause_write_en, current_priority_write_en, previous_priority_write_en, mpie_write_en, mtval_write_en, mtvec_write_en, mie_csr_write_en, mscratch_write_en;
wire [31:0] csr_wdata;

// Address-match signals: "which CSR is this instruction pointing at" (used for READING).
wire mepc_sel, mie_sel, mcause_sel, current_priority_sel, previous_priority_sel, mpie_sel, mtval_sel, mtvec_sel, mie_csr_sel, mip_sel, mscratch_sel, misa_sel;

// New CSRs
wire [31:0] mscratch_val, misa_val;

// csrrs/csrrc/csrrsi/csrrci (funct3[1] = 1) with rs1/uimm = 0 only read: they must not write.
wire csr_write_EX = IsCSR_EX & HREADY & ~(Instr_EX[13] & (Instr_EX[19:15] == 5'd0));

assign mepc_write_en              = mepc_sel              & csr_write_EX;
assign mie_write_en               = mie_sel               & csr_write_EX;
assign mcause_write_en            = mcause_sel            & csr_write_EX;
assign current_priority_write_en  = current_priority_sel  & csr_write_EX;
assign previous_priority_write_en = previous_priority_sel & csr_write_EX;
assign mpie_write_en              = mpie_sel              & csr_write_EX;
assign mtval_write_en             = mtval_sel             & csr_write_EX;
// mtvec, mie (0x304) and mscratch have no trap-priority logic inside their registers, so block their write here:
// an interrupt squashes the instruction in EX, which re-executes after mret.
assign mtvec_write_en             = mtvec_sel             & csr_write_EX & ~interrupt_taken;
assign mie_csr_write_en           = mie_csr_sel           & csr_write_EX & ~interrupt_taken;
assign mscratch_write_en          = mscratch_sel          & csr_write_EX & ~interrupt_taken;
// mip (0x344) is read-only: no write path.
// misa (0x301) is WARL and hardwired: writes are silently ignored, no write path, no exception.
wire [31:0] csr_read_val_EX;

// ============ CSR WRITE BYPASSES ============
// A CSR write sitting in EX only lands in its register at the end of the cycle. Anything in ID that needs the NEW value
// in this same cycle must take it from csr_wdata instead of from the register.

// (1) mret in ID redirects the PC to mepc: use the value being written to mepc, if there is one.
wire [31:0] mepc_for_mret = mepc_write_en ? {csr_wdata[31:2], 2'b00} : mepc_val;

// (2) mret in ID restores current_priority <= previous_priority: use the value being written to previous_priority, if there is one.
wire [1:0] pprio_for_mret = previous_priority_write_en ? csr_wdata[1:0] : previous_priority_val;

// (3) mret in ID restores MIE <= MPIE and sets MPIE <= 1: use the MPIE value being written by an mstatus write in EX.
//     mie.v and mpie.v let a CSR write beat mret, so the write enables are gated off while a valid mret is in ID:
//     the program order is "write mstatus, then mret", so the mret result is the final one.
wire mpie_for_mret = mpie_write_en ? csr_wdata[7] : mpie_val;
wire mie_write_en_final  = mie_write_en  & ~Mret_valid_ID;
wire mpie_write_en_final = mpie_write_en & ~Mret_valid_ID;

// (4) a trap raised from ID in the same cycle as an mtvec write in EX: the write is older, so the trap vector uses the new value.
//     (mtvec_write_en already includes ~interrupt_taken: an interrupt squashes the csr instruction, so the old mtvec stays.)
wire [31:0] mtvec_for_trap = mtvec_write_en ? {csr_wdata[31:2], 1'b0, csr_wdata[0]} : mtvec_val;

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
    .HREADY(HREADY),
    .EX_RedirectPC(EX_RedirectPC_EX),
    .mepc(mepc_for_mret),
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
    .HREADY(HREADY),
    .Predicted_Taken_In(Predicted_Taken_IF),
    .Instr_In(Instr_IF),
    .PC_In(PC_IF),
    .PC_Plus_4_In(PCPlus4_IF),
    .Instr_Out(Instr_ID),
    .PC_Out(PC_ID),
    .PC_Plus_4_Out(PCPlus4_ID),
    .Predicted_Taken_Out(Predicted_Taken_ID),
    .instruction_access_fault_In(instruction_access_fault_IF),
    .instruction_access_fault_Out(instruction_access_fault_ID),
    .Valid_Out(Valid_ID)
);

ID_stage ID_stage_inst
(
    .clk(clk),
    .we(RegWrite_WB & HREADY),
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
    .HREADY(HREADY),
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
    .Valid_In(Valid_ID),
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
    .IsLoad_Out(IsLoad_EX),
    .Valid_Out(Valid_EX)
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
    .HREADY(HREADY),
    .PC_Plus_4_In(PCPlus4_EX),
    .ALUResult_In(Result_EX),
    .RD2_In(ForwardedRD2),
    .csr_read_val_In(csr_read_val_EX),
    .WA_In(WA_EX),
    .Funct3_In(Funct3_EX),
    .Width_In(Width_EX),
    .ResultSrc_In(ResultSrc_EX),
    .RegWrite_In(RegWrite_EX),
    .IsLoad_In(IsLoad_EX),
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
    .IsLoad_Out(IsLoad_MEM),
    .MemWrite_Out(MemWrite_MEM)
);

// Address phase of the bus transfer: driven from the MEM-stage registers.
// The data phase (HWDATA / HRDATA) happens one cycle later, while the instruction is in WB.
AHB_master_CPU_interface AHB_master_CPU_interface_inst
(
    .IsLoad_MEM(IsLoad_MEM),
    .MemWrite_MEM(MemWrite_MEM),
    .Width_MEM(Width_MEM),
    .ALUResult_MEM(ALUResult_MEM),
    .RD2_WB(RD2_WB),
    .HWRITE(HWRITE),
    .HTRANS(HTRANS),
    .HSIZE(HSIZE),
    .HADDR(HADDR),
    .HWDATA(HWDATA)
);

MEM_WB_reg MEM_WB_reg_inst
(
    .clk(clk),
    .reset(reset),
    .HREADY(HREADY),
    .PC_Plus_4_In(PCPlus4_MEM),
    .ALUResult_In(ALUResult_MEM),
    .csr_read_val_In(csr_read_val_MEM),
    .RD2_In(RD2_MEM),
    .WA_In(WA_MEM),
    .Funct3_In(Funct3_MEM),
    .ResultSrc_In(ResultSrc_MEM),
    .RegWrite_In(RegWrite_MEM),
    .IsLoad_In(IsLoad_MEM),
    .MemWrite_In(MemWrite_MEM),
    .PC_Plus_4_Out(PCPlus4_WB),
    .ALUResult_Out(ALUResult_WB),
    .csr_read_val_Out(csr_read_val_WB),
    .RD2_Out(RD2_WB),
    .WA_Out(WA_WB),
    .Funct3_Out(Funct3_WB),
    .ResultSrc_Out(ResultSrc_WB),
    .RegWrite_Out(RegWrite_WB),
    .IsLoad_Out(IsLoad_WB),
    .MemWrite_Out(MemWrite_WB)
);

// Load data arrives from the bus in WB: sign/zero-extend it here.
load_extend load_extend_inst
(
    .Funct3(Funct3_WB),
    .HRDATA(HRDATA),
    .ReadData(ReadData_WB)
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
    .previous_priority(pprio_for_mret),                 // bypassed: a previous_priority write in EX is visible to an mret in ID
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

mtval mtval_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_taken(interrupt_taken),
    .exception_taken(exception_taken),
    .mtval_write_en(mtval_write_en),
    .mtval_in(mtval_next),
    .csr_wdata(csr_wdata),
    .mtval_out(mtval_val)
);

mtvec mtvec_inst
(
    .clk(clk),
    .reset(reset),
    .mtvec_write_en(mtvec_write_en),
    .csr_wdata(csr_wdata),
    .mtvec_out(mtvec_val)
);

pc_mtvec_mcause pc_mtvec_mcause_inst
(
    .mtvec_out(mtvec_for_trap),                         // bypassed: an mtvec write in EX is visible to a trap raised from ID
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
    .mie_write_en(mie_write_en_final),                  // an mstatus write in EX loses to a valid mret in ID
    .csr_wdata_b0(csr_wdata[3]),
    .mpie_out(mpie_for_mret),                           // bypassed: the MPIE value being written, if any
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
    .mpie_write_en(mpie_write_en_final),                // an mstatus write in EX loses to a valid mret in ID
    .mie_out(mie_val),
    .mie_wdata(csr_wdata[3]),
    .mpie_wdata(csr_wdata[7]),
    .mie_write_en(mie_write_en),                        // ungated on purpose: only used for the trap-in-same-cycle case
    .mpie_out(mpie_val)
);

// mie CSR (0x304): per-source interrupt enables (bit 11 external, bit 7 timer)
mie_csr mie_csr_inst
(
    .clk(clk),
    .reset(reset),
    .mie_csr_write_en(mie_csr_write_en),
    .csr_wdata(csr_wdata),
    .mie_csr_out(mie_csr_val)
);

// mscratch (0x340): plain read/write scratch register
mscratch mscratch_inst
(
    .clk(clk),
    .reset(reset),
    .mscratch_write_en(mscratch_write_en),
    .csr_wdata(csr_wdata),
    .mscratch_out(mscratch_val)
);

// misa (0x301): hardwired RV32I, writes ignored
misa misa_inst
(
    .misa_out(misa_val)
);

csr_addr_decoder csr_addr_decoder_inst
(
    .csr_addr(Instr_EX[31:20]),
    .IsCSR(IsCSR_EX),
    .mepc_sel(mepc_sel),
    .mie_sel(mie_sel),
    .mcause_sel(mcause_sel),
    .current_priority_sel(current_priority_sel),
    .previous_priority_sel(previous_priority_sel),
    .mpie_sel(mpie_sel),
    .mtval_sel(mtval_sel),
    .mtvec_sel(mtvec_sel),
    .mie_csr_sel(mie_csr_sel),
    .mip_sel(mip_sel),
    .mscratch_sel(mscratch_sel),
    .misa_sel(misa_sel)
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
    .mepc_sel(mepc_sel),
    .mie_sel(mie_sel),
    .mcause_sel(mcause_sel),
    .current_priority_sel(current_priority_sel),
    .previous_priority_sel(previous_priority_sel),
    .mpie_sel(mpie_sel),
    .mtval_sel(mtval_sel),
    .mtvec_sel(mtvec_sel),
    .mie_csr_sel(mie_csr_sel),
    .mip_sel(mip_sel),
    .mscratch_sel(mscratch_sel),
    .misa_sel(misa_sel),
    .pending_keyboard(pending_keyboard),
    .pending_disk(pending_disk),
    .mie_csr_val(mie_csr_val),
    .mtval_val(mtval_val),
    .mtvec_val(mtvec_val),
    .mscratch_val(mscratch_val),
    .misa_val(misa_val),
    .mie_val(mie_val),
    .mpie_val(mpie_val),
    .mepc_val(mepc_val),
    .mcause_val(mcause_val),
    .current_priority(current_priority_val),
    .previous_priority(previous_priority_val),
    .csr_read_val(csr_read_val_EX)
);

endmodule