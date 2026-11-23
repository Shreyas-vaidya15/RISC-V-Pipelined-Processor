// IF stage with the instruction memory on the bus (instruction bus, stage 1).
//
// Two things now happen in two different cycles:
//   address phase : PC register is put on HADDR_fetch (cycle c)
//   data phase    : the instruction comes back on HRDATA_fetch (cycle c+1)
//
// The outputs PC / PCPlus4 / Instr / Predicted_Taken / Valid / instruction_access_fault all describe the
// instruction that is in its DATA phase now (the one that goes into IF_ID_reg at the end of this cycle).
// The PC REGISTER (the next address to fetch) stays inside this module as PC_reg.
//
// The front end "advances" exactly when IF_ID_reg would capture a new instruction. Only then is a new
// fetch address sent out. Whenever the front end does not advance (frozen or flushed) no address is sent.
// If an instruction is arriving while the front end is frozen, it is saved in a one-entry buffer (skid_*).
module IF_stage #(parameter DEPTH = 256)
(
input clk, reset, Stall, EX_Override, Mret_taken, interrupt_taken, exception_taken, pipe_ready,
input [31:0] EX_RedirectPC, mepc, pc_mtvec_mcause,
input [31:0] HRDATA_fetch,                  // instruction coming back from the bus (data phase)
output [31:0] HADDR_fetch,                  // fetch address phase
output [1:0] HTRANS_fetch,
output [31:0] PC, PCPlus4, Instr,           // the instruction in its data phase
output Predicted_Taken,
output instruction_access_fault,
output Valid
);

localparam [31:0] NOP = 32'h00000013;   // addi x0, x0, 0

// ---------------- front end control ----------------
// same four signals that make IF_ID_reg load a bubble
wire flush_front = EX_Override | Mret_taken | interrupt_taken | exception_taken;

// IF_ID_reg captures the instruction in its data phase, and a new fetch address goes out
wire advance = pipe_ready & ~Stall & ~flush_front;

// IF_ID_reg loads a bubble: the instruction in its data phase is thrown away
wire discard = pipe_ready & flush_front;

// anything else (~pipe_ready, or Stall without a flush): frozen, the arriving instruction is kept in the buffer

// ---------------- address phase ----------------
wire [31:0] PC_reg, PC_reg_plus4, PC_Next;
wire fault_pc;                          // address out of range: no bus transfer, a nop + fault flag goes down the pipe

instruction_access_fault #(.DEPTH(DEPTH)) instruction_access_fault_inst
(
    .PC_IF(PC_reg),
    .instruction_access_fault(fault_pc)
);

assign HADDR_fetch  = PC_reg;
assign HTRANS_fetch = (advance & ~fault_pc) ? 2'b10 : 2'b00;

// ---------------- the fetch whose data phase is on the bus now ----------------
reg        inflight_valid, inflight_fault;
reg [31:0] inflight_pc;

// ---------------- one-entry buffer: instruction that arrived while the front end was frozen ----------------
reg        skid_valid, skid_fault;
reg [31:0] skid_pc, skid_instr;

// what is "in IF" this cycle: the buffered instruction if there is one, otherwise the one arriving from the bus
wire        present_valid = skid_valid | inflight_valid;
wire [31:0] present_pc    = skid_valid ? skid_pc    : inflight_pc;
wire        present_fault = skid_valid ? skid_fault : inflight_fault;
wire [31:0] present_raw   = skid_valid ? skid_instr : HRDATA_fetch;

// no instruction (bubble) or out-of-range fetch -> a clean nop, so the predictor and the decoder never see garbage
assign Instr = (present_valid & ~present_fault) ? present_raw : NOP;
assign instruction_access_fault = present_valid & present_fault;
assign Valid = present_valid;

// a bubble looks the same as a flushed IF_ID_reg: PC fields 0
assign PC      = present_valid ? present_pc : 32'b0;
assign PCPlus4 = present_valid ? present_pc + 32'd4 : 32'b0;

// ---------------- prediction (acts on the instruction in its data phase) ----------------
// JAL always jumps, so it is redirected here in fetch; EX_stage no longer redirects for it
wire is_jal = (Instr[6:0] == 7'b1101111);
assign Predicted_Taken = (Instr[31] & (Instr[6:0] == 7'b1100011)) | is_jal;
wire [31:0] ImmExt, PC_Predict_Target;
// J-type immediate for JAL, B-type immediate for branches
assign ImmExt = is_jal ? {{12{Instr[31]}}, Instr[19:12], Instr[20], Instr[30:21], 1'b0} : {{20{Instr[31]}}, Instr[7], Instr[30:25], Instr[11:8], 1'b0};

pc_plus_4 pc_plus_4_inst(
    .PC(PC_reg),
    .PCPlus4(PC_reg_plus4)
);

pc_target pc_target_predict_inst(
    .PCTarget(PC_Predict_Target),
    .PC(present_pc),                    // target is relative to the PC of the instruction that was fetched
    .ImmExt(ImmExt)
);

pc_mux pc_mux_inst(
    .PC_Next(PC_Next),
    .PC_Target_Predicted(PC_Predict_Target),
    .PC_Plus_4(PC_reg_plus4),
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
    .PC(PC_reg),
    .PCNext(PC_Next),
    .pc_mtvec_mcause(pc_mtvec_mcause),
    .clk(clk),
    .reset(reset),
    .Stall(Stall),
    .interrupt_taken(interrupt_taken),
    .exception_taken(exception_taken),
    .pipe_ready(pipe_ready)
);

// ---------------- in-flight register and buffer ----------------
always @(posedge clk or posedge reset)
begin
    if (reset)
    begin
        inflight_valid <= 1'b0;
        inflight_fault <= 1'b0;
        inflight_pc    <= 32'b0;
        skid_valid     <= 1'b0;
        skid_fault     <= 1'b0;
        skid_pc        <= 32'b0;
        skid_instr     <= 32'b0;
    end

    else
    begin
        // address phase sent this cycle -> data phase next cycle.
        // A predicted-taken jump/branch moves the PC, so the address sent this cycle (PC+4) is the wrong path: drop it.
        if (advance)
        begin
            inflight_valid <= ~Predicted_Taken;
            inflight_fault <= fault_pc;
            inflight_pc    <= PC_reg;
        end
        else
        begin
            inflight_valid <= 1'b0;     // nothing was sent
        end

        // the instruction in its data phase was taken (advance) or thrown away (discard): buffer empty.
        // Otherwise keep it in the buffer (if it was already there this just rewrites the same values).
        if (advance | discard)
        begin
            skid_valid <= 1'b0;
        end
        else
        begin
            skid_valid <= present_valid;
            skid_pc    <= present_pc;
            skid_fault <= present_fault;
            skid_instr <= present_raw;
        end
    end
end

endmodule