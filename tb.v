module tb();

reg clk, reset, interrupt_keyboard, interrupt_disk;

top top_inst (
    .clk(clk),
    .reset(reset),
    .interrupt_keyboard(interrupt_keyboard),
    .interrupt_disk(interrupt_disk)
);

always #5 clk = ~clk;

// ------------------------------------------------------------------
// Convenience aliases
// ------------------------------------------------------------------
wire [31:0] PC_EX = top_inst.PC_EX;

`define REG(n) top_inst.ID_stage_inst.register_file_inst.registers[n]

// ------------------------------------------------------------------
// Injection points (byte addresses in instruction_memory.v)
//   main program triggers : 12,20,28,36,44,52,60,68   (phases A..H)
//   KB  ISR  "addi x30" (mie already 1)  : 296
//   DSK ISR  "addi x30" (mie already 1)  : 424
//   KB  ISR  "csrrs x29,mepc" (mie still 0, unsafe window) : 268
// ------------------------------------------------------------------
localparam KB_MIE1_PC   = 296;
localparam DSK_MIE1_PC  = 424;
localparam KB_UNSAFE_PC = 268;
localparam MAIN_END_PC  = 76;    // jal x0,512
localparam TRUE_END_PC  = 512;

// ------------------------------------------------------------------
// Pulse helpers: 1-cycle wide, asserted at negedge so the following
// posedge samples it exactly once into the pending latch.
// ------------------------------------------------------------------
task pulse_kb;
begin
    @(negedge clk); interrupt_keyboard = 1'b1; #10; interrupt_keyboard = 1'b0;
end
endtask

task pulse_disk;
begin
    @(negedge clk); interrupt_disk = 1'b1; #10; interrupt_disk = 1'b0;
end
endtask

task pulse_both;
begin
    @(negedge clk);
    interrupt_keyboard = 1'b1; interrupt_disk = 1'b1;
    #10;
    interrupt_keyboard = 1'b0; interrupt_disk = 1'b0;
end
endtask

// ------------------------------------------------------------------
// Checking infrastructure
// ------------------------------------------------------------------
integer errors;
integer trap_idx;
integer min_sp, sp_now;
reg     trace;

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

// state that must hold after every phase has fully unwound
task phase_check;
    input [8*2-1:0] name;
    input integer   exp_traps;
begin
    $display("--- end of phase %0s (t=%0t) ---", name, $time);
    check("sp",        `REG(2),  200);
    check("x6  (live)", `REG(6),  111);
    check("x7  (live)", `REG(7),  222);
    check("x30 trap count", `REG(30), exp_traps);
    check("traps logged", trap_idx, exp_traps);
end
endtask

// Expected trap sequence: {cause code, mepc}
//   cause 7 = keyboard, 27 = disk
reg [31:0] exp_cause [0:14];
reg [31:0] exp_mepc  [0:14];

initial begin
    // A: keyboard alone
    exp_cause[0]  = 7;  exp_mepc[0]  = 16;
    // B: disk alone
    exp_cause[1]  = 27; exp_mepc[1]  = 24;
    // C: simultaneous -> disk first, keyboard after disk's mret (same return PC)
    exp_cause[2]  = 27; exp_mepc[2]  = 32;
    exp_cause[3]  = 7;  exp_mepc[3]  = 32;
    // D: kb outer, disk nests (2 >= 1) right after the addi @296
    exp_cause[4]  = 7;  exp_mepc[4]  = 40;
    exp_cause[5]  = 27; exp_mepc[5]  = 300;
    // E: disk outer, kb pulse @424 BLOCKED (1 < 2) until disk's mret
    exp_cause[6]  = 27; exp_mepc[6]  = 48;
    exp_cause[7]  = 7;  exp_mepc[7]  = 48;
    // F: kb outer, kb self-nests (1 >= 1)
    exp_cause[8]  = 7;  exp_mepc[8]  = 56;
    exp_cause[9]  = 7;  exp_mepc[9]  = 300;
    // G: kb outer, disk asserted @268 (mie=0) -> held, fires when mie<=1 executes (mepc=296)
    exp_cause[10] = 7;  exp_mepc[10] = 64;
    exp_cause[11] = 27; exp_mepc[11] = 296;
    // H: kb outer, kb self-nests twice (3-level)
    exp_cause[12] = 7;  exp_mepc[12] = 72;
    exp_cause[13] = 7;  exp_mepc[13] = 300;
    exp_cause[14] = 7;  exp_mepc[14] = 300;
end

// Trap monitor (sampled at negedge: interrupt_taken is combinational and stable there)
always @(negedge clk) begin
    if (!reset && top_inst.interrupt_taken) begin
        if (trap_idx < 15) begin
            $display(">>> TRAP #%0d  cause=%0d  mepc(PC_EX)=%0d  cur_prio=%0d  t=%0t",
                     trap_idx, top_inst.mcause_next[30:0], PC_EX,
                     top_inst.current_priority_val, $time);
            if (top_inst.mcause_next[30:0] !== exp_cause[trap_idx][30:0] ||
                PC_EX !== exp_mepc[trap_idx]) begin
                errors = errors + 1;
                $display("  [FAIL] trap #%0d expected cause=%0d mepc=%0d",
                         trap_idx, exp_cause[trap_idx], exp_mepc[trap_idx]);
            end
        end
        else begin
            errors = errors + 1;
            $display(">>> [FAIL] UNEXPECTED EXTRA TRAP #%0d cause=%0d mepc=%0d",
                     trap_idx, top_inst.mcause_next[30:0], PC_EX);
        end
        trap_idx = trap_idx + 1;
    end
end

// Track deepest stack usage (sp starts at 200, each frame = 32 bytes)
always @(negedge clk) begin
    if (!reset) begin
        sp_now = `REG(2);
        if (sp_now != 0 && sp_now < min_sp) min_sp = sp_now;
    end
end

// ------------------------------------------------------------------
// Watchdog (only catches hangs; full run needs ~6000ns)
// ------------------------------------------------------------------
initial begin
    #30000;
    $display("---WATCHDOG FIRED: a wait() never resolved, main sequence stuck---");
    $display("x2(sp)=%0d x30=%0d PC_EX=%0d mepc=%0d mcause=%0d trap_idx=%0d",
        `REG(2), `REG(30), PC_EX, top_inst.mepc_val, top_inst.mcause_val, trap_idx);
    $finish;
end

// ------------------------------------------------------------------
// Main stimulus
// ------------------------------------------------------------------
initial begin
    reset = 1'b1;
    clk = 1'b0;
    interrupt_keyboard = 1'b0;
    interrupt_disk = 1'b0;
    errors = 0;
    trap_idx = 0;
    min_sp = 1000;
    trace = 1'b1;

    #23;
    reset = 1'b0;

    // ---- Phase A: keyboard alone ----
    wait (PC_EX == 12);
    pulse_kb;

    // ---- Phase B: disk alone ----
    wait (PC_EX == 20);
    phase_check("A", 1);
    pulse_disk;

    // ---- Phase C: simultaneous (disk wins, kb waits for disk's mret) ----
    wait (PC_EX == 28);
    phase_check("B", 2);
    pulse_both;

    // ---- Phase D: kb outer, disk nests after mie<=1 in KB ISR ----
    wait (PC_EX == 36);
    phase_check("C", 4);
    pulse_kb;
    wait (PC_EX == KB_MIE1_PC);
    pulse_disk;

    // ---- Phase E: disk outer, kb pulse in DISK ISR must be blocked until mret ----
    wait (PC_EX == 44);
    phase_check("D", 6);
    pulse_disk;
    wait (PC_EX == DSK_MIE1_PC);
    pulse_kb;

    // ---- Phase F: kb outer, kb self-nests (2-level) ----
    wait (PC_EX == 52);
    phase_check("E", 8);
    pulse_kb;
    wait (PC_EX == KB_MIE1_PC);
    pulse_kb;

    // ---- Phase G: unsafe window -- disk asserted while KB ISR still has mie=0 ----
    wait (PC_EX == 60);
    phase_check("F", 10);
    pulse_kb;
    wait (PC_EX == KB_UNSAFE_PC);
    pulse_disk;

    // ---- Phase H: kb self-nests twice (3-level) ----
    wait (PC_EX == 68);
    phase_check("G", 12);
    pulse_kb;
    wait (PC_EX == KB_MIE1_PC);   // level-1 ISR
    pulse_kb;
    wait (PC_EX == KB_MIE1_PC);   // level-2 ISR
    pulse_kb;

    wait (PC_EX == MAIN_END_PC);
    phase_check("H", 15);

    // ---- let the pipeline reach and finish the TRUE END marker ----
    wait (PC_EX == TRUE_END_PC);
    repeat (8) @(posedge clk);

    $display("---FINAL---");
    check("x2  (sp)",          `REG(2),  200);
    check("x6",                `REG(6),  111);
    check("x7",                `REG(7),  222);
    check("x20 (last trigger)", `REG(20), 15);
    check("x21 (last post)",    `REG(21), 16);
    check("x28 (end marker)",   `REG(28), 999);
    check("x30 (trap count)",   `REG(30), 15);
    check("total traps",        trap_idx, 15);
    check("deepest sp (3 lvl)", min_sp,   104);
    check("mie",                top_inst.mie_val, 1);
    check("current_priority",   top_inst.current_priority_val, 0);
    check("pending_keyboard",   top_inst.pending_keyboard, 0);
    check("pending_disk",       top_inst.pending_disk, 0);

    if (errors == 0) $display("=== ALL CHECKS PASSED ===");
    else             $display("=== %0d CHECK(S) FAILED ===", errors);
    $finish;
end

// ------------------------------------------------------------------
// Per-cycle trace
// ------------------------------------------------------------------
always @(posedge clk) begin
    if (!reset && trace)
        $display("t=%0t PC_EX=%0d mie=%b cur=%0d prev=%0d pend_kb=%b pend_dk=%b kb_tk=%b dk_tk=%b mepc=%0d mcause=%0d sp=%0d x6=%0d x7=%0d x30=%0d",
            $time, PC_EX, top_inst.mie_val,
            top_inst.current_priority_val, top_inst.previous_priority_val,
            top_inst.pending_keyboard, top_inst.pending_disk,
            top_inst.interrupt_keyboard_taken, top_inst.interrupt_disk_taken,
            top_inst.mepc_val, top_inst.mcause_val,
            `REG(2), `REG(6), `REG(7), `REG(30));
end

initial begin
    $dumpfile("waves.vcd");
    $dumpvars();
end

endmodule