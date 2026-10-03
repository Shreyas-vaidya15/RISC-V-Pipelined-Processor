module tb_iaf2();

// Self-checking testbench for the EXTRA INSTRUCTION ACCESS FAULT cases (see instruction_memory_iaf2.v):
//   1  forward branch predicted not-taken, really taken to an out-of-range target
//   2  mret with an out-of-range mepc
//   4  jal to an out-of-range AND misaligned target  -> cause 0 at the jal (not cause 1)
//   3  older load exception (cause 4 / 5) in EX in the same cycle as the out-of-range fetch in ID -> older wins, fetch re-faults after mret
//   3c valid load at the last word completes, then the fetch faults
// Build line at the bottom.

parameter TRACE = 0;   // set to 1 for a per-cycle trace

reg clk, reset, interrupt_keyboard, interrupt_disk;

top top_inst (
    .clk(clk),
    .reset(reset),
    .interrupt_keyboard(interrupt_keyboard),
    .interrupt_disk(interrupt_disk)
);

always #5 clk = ~clk;

wire [31:0] PC_EX = top_inst.PC_EX;

`define REG(n) top_inst.ID_stage_inst.register_file_inst.registers[n]

// ------------------------------------------------------------------
// Addresses (must match instruction_memory_iaf2.v)
// ------------------------------------------------------------------
localparam EXC_VEC = 100;              // mtvec (exceptions)
localparam INST_BYTES = 1024;          // instruction memory size in bytes (DEPTH 256 * 4)
localparam NTRAPS = 8;
localparam C2_START = 244, C4_START = 292, C3A_START = 316, C3B_START = 340, C3C_START = 364;
localparam END_MARK = 396, END_LOOP = 400;

// ------------------------------------------------------------------
// Checking infrastructure
// ------------------------------------------------------------------
integer errors;
integer trap_idx;
reg     post_trap_chk;       // "at the next negedge, PC must be at the vector"
reg     post_mem_chk;        // "at the next negedge, MEM stage must be a bubble" (EX-sourced traps only)

task check;
    input [8*22-1:0] what;
    input integer    got;
    input integer    exp;
begin
    if (got !== exp) begin
        errors = errors + 1;
        $display("  [FAIL] %0s: got %0d, expected %0d", what, got, exp);
    end
    else
        $display("  [ ok ] %0s = %0d", what, got);
end
endtask

// Expected traps: cause, mepc, source (1 = ID stage, 0 = EX stage), and whether the out-of-range fetch must be sitting in ID at that moment
reg [31:0] exp_cause   [0:NTRAPS-1];
reg [31:0] exp_mepc    [0:NTRAPS-1];
reg        exp_src     [0:NTRAPS-1];
reg        exp_idf_chk [0:NTRAPS-1];
initial begin
    exp_cause[0] = 1; exp_mepc[0] = 1216; exp_src[0] = 1; exp_idf_chk[0] = 0;
    exp_cause[1] = 1; exp_mepc[1] = 2000; exp_src[1] = 1; exp_idf_chk[1] = 0;
    exp_cause[2] = 0; exp_mepc[2] = 300; exp_src[2] = 0; exp_idf_chk[2] = 0;
    exp_cause[3] = 4; exp_mepc[3] = 1020; exp_src[3] = 0; exp_idf_chk[3] = 1;
    exp_cause[4] = 1; exp_mepc[4] = 1024; exp_src[4] = 1; exp_idf_chk[4] = 0;
    exp_cause[5] = 5; exp_mepc[5] = 1020; exp_src[5] = 0; exp_idf_chk[5] = 1;
    exp_cause[6] = 1; exp_mepc[6] = 1024; exp_src[6] = 1; exp_idf_chk[6] = 0;
    exp_cause[7] = 1; exp_mepc[7] = 1024; exp_src[7] = 1; exp_idf_chk[7] = 0;
end

wire [31:0] trap_mepc = top_inst.interrupt_taken ? top_inst.PC_EX : top_inst.exception_mepc;

// Trap monitor + invariants (sampled at negedge, when everything is stable)
always @(negedge clk) begin
    // --- one cycle after a trap: fetch must have been redirected to the vector ---
    if (post_trap_chk) begin
        post_trap_chk = 1'b0;
        if (top_inst.PC_IF !== EXC_VEC) begin
            errors = errors + 1;
            $display("  [FAIL] after trap, PC_IF = %0d, expected vector %0d", top_inst.PC_IF, EXC_VEC);
        end
    end

    // --- after an EX-sourced trap the squashed instruction must not reach MEM ---
    if (post_mem_chk) begin
        post_mem_chk = 1'b0;
        if (top_inst.RegWrite_MEM !== 1'b0 || top_inst.MemWrite_MEM !== 1'b0 || top_inst.WA_MEM !== 5'd0 || top_inst.ALUResult_MEM !== 32'd0) begin
            errors = errors + 1;
            $display("  [FAIL] after an EX-sourced trap the MEM stage is not a bubble (RegWrite=%b MemWrite=%b WA=%0d ALUResult=%0d)",
                     top_inst.RegWrite_MEM, top_inst.MemWrite_MEM, top_inst.WA_MEM, top_inst.ALUResult_MEM);
        end
    end

    // --- an out-of-range fetch must NEVER reach EX (it is a nop that must be squashed) ---
    if (!reset && PC_EX >= INST_BYTES) begin
        errors = errors + 1;
        $display("  [FAIL] an instruction fetched from out-of-range PC=%0d (0x%0h) reached EX", PC_EX, PC_EX);
    end

    if (!reset && (top_inst.interrupt_taken || top_inst.exception_taken)) begin
        if (trap_idx < NTRAPS) begin
            $display(">>> TRAP #%0d  %0s  cause=0x%0h  mepc=0x%0h  (expected cause=0x%0h mepc=0x%0h)  fault_in_ID=%b  t=%0t",
                     trap_idx, top_inst.interrupt_taken ? "INT" : (top_inst.exception_taken_EX ? "EXC(EX)" : "EXC(ID)"),
                     top_inst.mcause_next, trap_mepc, exp_cause[trap_idx], exp_mepc[trap_idx],
                     top_inst.instruction_access_fault_ID, $time);
            if (top_inst.interrupt_taken) begin
                errors = errors + 1;
                $display("  [FAIL] trap #%0d: no interrupt is expected in this test", trap_idx);
            end
            if (top_inst.mcause_next !== exp_cause[trap_idx] || trap_mepc !== exp_mepc[trap_idx]) begin
                errors = errors + 1;
                $display("  [FAIL] trap #%0d expected cause=0x%0h mepc=0x%0h", trap_idx, exp_cause[trap_idx], exp_mepc[trap_idx]);
            end
            if (exp_src[trap_idx]) begin
                // must come from the ID stage
                if (top_inst.exception_taken_ID !== 1'b1 || top_inst.exception_taken_EX !== 1'b0 || top_inst.instruction_access_fault_ID !== 1'b1) begin
                    errors = errors + 1;
                    $display("  [FAIL] trap #%0d should come from the ID stage with the fetch-fault flag set", trap_idx);
                end
            end
            else begin
                // must come from the EX stage, and the older instruction wins
                if (top_inst.exception_taken_EX !== 1'b1 || top_inst.exception_taken_ID !== 1'b0) begin
                    errors = errors + 1;
                    $display("  [FAIL] trap #%0d should come from the EX stage only (exception_taken_EX=%b exception_taken_ID=%b)",
                             trap_idx, top_inst.exception_taken_EX, top_inst.exception_taken_ID);
                end
                if (exp_idf_chk[trap_idx] && top_inst.instruction_access_fault_ID !== 1'b1) begin
                    errors = errors + 1;
                    $display("  [FAIL] trap #%0d: the out-of-range fetch should be sitting in ID in this cycle (test is not hitting the case)", trap_idx);
                end
                post_mem_chk = 1'b1;
            end
        end
        else begin
            errors = errors + 1;
            $display(">>> [FAIL] UNEXPECTED EXTRA TRAP #%0d cause=0x%0h", trap_idx, top_inst.mcause_next);
        end
        trap_idx = trap_idx + 1;
        post_trap_chk = 1'b1;
    end
end

// ------------------------------------------------------------------
// Watchdog (only catches hangs)
// ------------------------------------------------------------------
initial begin
    #40000;
    $display("---WATCHDOG FIRED: a wait() never resolved---");
    $display("PC_EX=%0d trap_idx=%0d x30=%0d", PC_EX, trap_idx, `REG(30));
    $finish;
end

// ------------------------------------------------------------------
// Main stimulus: just let the program run and check each case
// ------------------------------------------------------------------
initial begin
    reset = 1'b1;
    clk = 1'b0;
    interrupt_keyboard = 1'b0;
    interrupt_disk = 1'b0;
    errors = 0;
    trap_idx = 0;
    post_trap_chk = 1'b0;
    post_mem_chk = 1'b0;

    #23;
    reset = 1'b0;

    // ---- case 1: forward branch predicted not-taken, really taken to an out-of-range target ----
    wait (PC_EX == C2_START);
    $display("--- end of case 1 ---");
    check("x20 marker (once)",   `REG(20), 1);
    check("x11 wrong path",      `REG(11), 0);
    check("traps so far",        trap_idx, 1);

    // ---- case 2: mret with a bad mepc ----
    wait (PC_EX == C4_START);
    $display("--- end of case 2 ---");
    check("x21 marker (once)",   `REG(21), 1);
    check("x12 wrong path",      `REG(12), 0);
    check("traps so far",        trap_idx, 2);

    // ---- case 4: jal to a misaligned + out-of-range target: cause 0 at the jal, link NOT written ----
    wait (PC_EX == C3A_START);
    $display("--- end of case 4 ---");
    check("x22 marker (once)",   `REG(22), 1);
    check("x1 (link not written)", `REG(1), 77);
    check("traps so far",        trap_idx, 3);

    // ---- case 3a: misaligned lw at the last word, then the fetch faults ----
    wait (PC_EX == C3B_START);
    $display("--- end of case 3a ---");
    check("x23 marker (once)",   `REG(23), 1);
    check("x16 (lw squashed)",   `REG(16), 77);
    check("traps so far",        trap_idx, 5);

    // ---- case 3b: out-of-range lw at the last word, then the fetch faults ----
    wait (PC_EX == C3C_START);
    $display("--- end of case 3b ---");
    check("x24 marker (once)",   `REG(24), 1);
    check("x16 (lw squashed)",   `REG(16), 77);
    check("traps so far",        trap_idx, 7);

    // ---- case 3c: valid lw at the last word completes, then the fetch faults ----
    wait (PC_EX == END_MARK);
    $display("--- end of case 3c ---");
    check("x25 marker (once)",   `REG(25), 1);
    check("x16 (lw completed)",  `REG(16), 1234);
    check("traps so far",        trap_idx, 8);

    wait (PC_EX == END_LOOP);
    repeat (8) @(posedge clk);

    $display("---FINAL---");
    check("x15 (end marker)",    `REG(15), 999);
    check("x30 (trap counter)",  `REG(30), 8);
    check("x29 (last cause)",    `REG(29), 1);
    check("total traps",         trap_idx, 8);
    check("mcause register",     top_inst.mcause_val, 1);
    check("mie",                 top_inst.mie_val, 1);
    check("current_priority",    top_inst.current_priority_val, 0);

    if (errors == 0) $display("=== ALL CHECKS PASSED ===");
    else             $display("=== %0d CHECK(S) FAILED ===", errors);
    $finish;
end

// ------------------------------------------------------------------
// Optional per-cycle trace (TRACE = 1)
// ------------------------------------------------------------------
always @(posedge clk) begin
    if (!reset && TRACE)
        $display("t=%0t PC_IF=%0d PC_ID=%0d PC_EX=%0d iaf_IF=%b iaf_ID=%b excID=%b excEX=%b ovr=%b mcause=%0d x30=%0d",
            $time, top_inst.PC_IF, top_inst.PC_ID, PC_EX, top_inst.instruction_access_fault_IF, top_inst.instruction_access_fault_ID,
            top_inst.exception_taken_ID, top_inst.exception_taken_EX, top_inst.EX_Override_EX,
            top_inst.mcause_val, `REG(30));
end

initial begin
    $dumpfile("waves_iaf2.vcd");
    $dumpvars();
end

endmodule

// Build (swap this instruction memory in for the normal one, and leave tb.v and any other tb out):
//   iverilog -s tb_iaf2 -o sim_iaf2 <all .v files except instruction_memory.v, instruction_memory_iaf.v and tb.v / tb_iaf.v> \
//            instruction_memory_iaf2.v tb_iaf2.v
//   vvp sim_iaf2