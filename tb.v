`timescale 1ns/1ps

// ============================================================================================
// INTERRUPT SWEEP TESTBENCH  (pairs with the "INTERRUPT SWEEP IMAGE" instruction_memory.v)
//
// Build (the image is THE instruction memory; leave out the old tb.v):
//   iverilog -s tb_sweep -o sim_sweep <all .v files except tb.v> tb_sweep.v
//   vvp sim_sweep
//
// Part 1  reference run: no interrupt. Checked against the image's golden tables (gr / gm),
//         and its final registers / data memory / CSRs are saved.
// Part 2  sweep: for each kind (keyboard, disk, both) and each injection cycle N = 0 .. ref_cycles+8,
//         reset to a fresh state, deliver ONE 1-cycle pulse at cycle N, run to the end marker, drain,
//         and compare against the reference run. The handler is transparent (only x23), so everything
//         except x23 must match; x23 must equal the number of interrupts expected.
// Part 3  reset in the middle of a handler: reset k cycles after a trap is taken, check that every
//         piece of trap state is back at its reset value, then run the whole program again and
//         compare with the reference run.
//
// The register file and data memory have no reset in the RTL, so this testbench clears them (hierarchically)
// every time it resets. Everything else is cleared by the real reset.
// ============================================================================================

module tb_sweep();

localparam DMEM_BYTES = 256;      // data_memory DEPTH (64 words) * 4
localparam LIMIT      = 6000;     // cycle limit for one run (hang detection)
localparam DRAIN      = 30;       // cycles to keep running after the end marker (lets a late pending trap finish)
localparam EXTRA      = 8;        // sweep this many cycles past the reference end
localparam MAXPRINT   = 40;       // max failing runs / checks printed in detail

reg clk, reset, interrupt_keyboard, interrupt_disk;

top top_inst (
    .clk(clk),
    .reset(reset),
    .interrupt_keyboard(interrupt_keyboard),
    .interrupt_disk(interrupt_disk)
);

// 4 KB of instruction memory (DEPTH is in words); also moves the instruction_access_fault limit
defparam top_inst.IF_stage_inst.DEPTH = 1024;

`define IM      top_inst.IF_stage_inst.instruction_memory_inst
`define REG(n)  top_inst.ID_stage_inst.register_file_inst.registers[n]
`define DMEM(i) top_inst.MEM_stage_inst.data_memory_inst.mem[i]

initial clk = 1'b0;
always #5 clk = ~clk;

// ---------------- bookkeeping ----------------
integer errors, warnings, prints;
integer cyc;
integer irq_cnt, exc_cnt, first_trap_pc;
integer ref_cycles;
integer runs, bad_runs;
reg     rec_ref;
reg     hang;

reg [31:0] ref_reg [0:31];
reg [7:0]  ref_mem [0:DMEM_BYTES-1];
reg [31:0] ref_mscratch, ref_mie_csr, ref_mtvec;
reg        ref_mie, ref_mpie;
reg [1:0]  ref_cprio;

reg [31:0] snap_reg [0:31];
reg [7:0]  snap_mem [0:DMEM_BYTES-1];
reg [31:0] snap_mscratch, snap_mie_csr, snap_mtvec;
reg        snap_mie, snap_mpie;
reg [1:0]  snap_cprio;

reg ref_exec [0:1023];            // word PCs that were valid in EX during the reference run
reg hit_int  [0:1023];            // word PCs that an interrupt was actually taken on (mepc)

// ---------------- trap monitor (negedge) ----------------
always @(negedge clk) begin
    if (!reset) begin
        if (top_inst.interrupt_taken) begin
            irq_cnt = irq_cnt + 1;
            if (irq_cnt == 1) first_trap_pc = top_inst.PC_EX;
            hit_int[top_inst.PC_EX[11:2]] = 1'b1;
        end
        if (top_inst.exception_taken)
            exc_cnt = exc_cnt + 1;
        if (rec_ref && top_inst.Valid_EX)
            ref_exec[top_inst.PC_EX[11:2]] = 1'b1;
    end
end

// ---------------- reset to a fresh state ----------------
// Returns with reset still asserted, at a negedge, after two clock edges with reset high.
task do_reset;
    integer j;
    begin
        @(negedge clk);
        reset = 1'b1;
        interrupt_keyboard = 1'b0;
        interrupt_disk     = 1'b0;
        for (j = 0; j < 32; j = j + 1)          `REG(j)  = 32'b0;
        for (j = 0; j < DMEM_BYTES; j = j + 1)  `DMEM(j) = 8'h00;
        irq_cnt = 0; exc_cnt = 0; first_trap_pc = -1;
        @(negedge clk);
        @(negedge clk);
    end
endtask

// ---------------- snapshot of the final state ----------------
task take_snapshot;
    integer j;
    begin
        for (j = 0; j < 32; j = j + 1)          snap_reg[j] = `REG(j);
        for (j = 0; j < DMEM_BYTES; j = j + 1)  snap_mem[j] = `DMEM(j);
        snap_mscratch = top_inst.mscratch_val;
        snap_mie_csr  = top_inst.mie_csr_val;
        snap_mtvec    = top_inst.mtvec_val;
        snap_mie      = top_inst.mie_val;
        snap_mpie     = top_inst.mpie_val;
        snap_cprio    = top_inst.current_priority_val;
    end
endtask

// ---------------- one complete run ----------------
// kind: 0 = no interrupt, 1 = keyboard, 2 = disk, 3 = both in the same cycle
// N   : cycle (counted from reset release) in which the 1-cycle pulse is applied
// Call do_reset first. Leaves a snapshot and the run length in cyc.
task run_to_end;
    input integer kind;
    input integer N;
    begin
        reset = 1'b0;
        cyc = 0;
        // keep going until the end marker is seen AND the pulse has been delivered
        while ((`REG(30) !== 32'd99 || cyc <= N) && cyc < LIMIT) begin
            interrupt_keyboard = (kind == 1 || kind == 3) && (cyc == N);
            interrupt_disk     = (kind == 2 || kind == 3) && (cyc == N);
            @(negedge clk);
            cyc = cyc + 1;
        end
        interrupt_keyboard = 1'b0;
        interrupt_disk     = 1'b0;
        hang = (cyc >= LIMIT);
        repeat (DRAIN) @(negedge clk);
        take_snapshot;
    end
endtask

// ---------------- compare snapshot with the reference run ----------------
// exp_traps: number of interrupts that must have been taken in this run
// tag      : text for the messages
task compare_to_ref;
    input integer exp_traps;
    input integer kind;
    input integer N;
    integer j, bad;
    begin
        bad = 0;

        if (hang) begin
            bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: HANG, end marker never reached (x30=%0d PC_IF=%0d)",
                                            kind, N, snap_reg[30], top_inst.PC_IF);
        end

        if (irq_cnt !== exp_traps) begin
            bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: %0d interrupts taken, expected %0d (first trap on mepc=%0d)",
                                            kind, N, irq_cnt, exp_traps, first_trap_pc);
        end
        if (snap_reg[23] !== exp_traps) begin
            bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: x23 (handler count) = %0d, expected %0d (first trap on mepc=%0d)",
                                            kind, N, snap_reg[23], exp_traps, first_trap_pc);
        end
        if (exc_cnt !== 0) begin
            bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: %0d exception(s) taken, expected none (first interrupt on mepc=%0d)",
                                            kind, N, exc_cnt, first_trap_pc);
        end

        for (j = 0; j < 32; j = j + 1)
            if (j != 23 && snap_reg[j] !== ref_reg[j]) begin
                bad = bad + 1;
                if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: x%0d = 0x%0h, reference 0x%0h (first trap on mepc=%0d)",
                                                kind, N, j, snap_reg[j], ref_reg[j], first_trap_pc);
            end

        for (j = 0; j < DMEM_BYTES; j = j + 1)
            if (snap_mem[j] !== ref_mem[j]) begin
                bad = bad + 1;
                if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: data mem[%0d] = 0x%0h, reference 0x%0h (first trap on mepc=%0d)",
                                                kind, N, j, snap_mem[j], ref_mem[j], first_trap_pc);
            end

        if (snap_mscratch !== ref_mscratch) begin bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: mscratch = 0x%0h, reference 0x%0h", kind, N, snap_mscratch, ref_mscratch); end
        if (snap_mie_csr !== ref_mie_csr) begin bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: mie csr = 0x%0h, reference 0x%0h", kind, N, snap_mie_csr, ref_mie_csr); end
        if (snap_mtvec !== ref_mtvec) begin bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: mtvec = 0x%0h, reference 0x%0h", kind, N, snap_mtvec, ref_mtvec); end
        if (snap_mie !== ref_mie) begin bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: mstatus.MIE = %b, reference %b", kind, N, snap_mie, ref_mie); end
        if (snap_mpie !== ref_mpie) begin bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: mstatus.MPIE = %b, reference %b", kind, N, snap_mpie, ref_mpie); end
        if (snap_cprio !== ref_cprio) begin bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: current_priority = %0d, reference %0d", kind, N, snap_cprio, ref_cprio); end

        if (top_inst.pending_keyboard || top_inst.pending_disk) begin
            bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: interrupt still pending at the end (kbd=%b disk=%b)",
                                            kind, N, top_inst.pending_keyboard, top_inst.pending_disk);
        end

        runs = runs + 1;
        if (bad != 0) begin
            bad_runs = bad_runs + 1;
            errors   = errors + bad;
            prints   = prints + 1;
        end
    end
endtask

// ---------------- reset-in-handler: one case ----------------
// pulse at cycle N, reset k cycles after the first trap is taken, check reset state, run again, compare
task run_mid_reset;
    input integer kind;
    input integer N;
    input integer k;
    reg got;
    integer bad;
    begin
        bad = 0;
        do_reset;
        reset = 1'b0;
        cyc = 0;
        got = 1'b0;
        while (!got && cyc < LIMIT) begin
            interrupt_keyboard = (kind == 1 || kind == 3) && (cyc == N);
            interrupt_disk     = (kind == 2 || kind == 3) && (cyc == N);
            @(negedge clk);
            cyc = cyc + 1;
            if (top_inst.interrupt_taken) got = 1'b1;
        end
        interrupt_keyboard = 1'b0;
        interrupt_disk     = 1'b0;

        if (!got) begin
            bad = bad + 1;
            $display("  [FAIL] reset-in-handler kind=%0d N=%0d: interrupt never taken", kind, N);
        end

        repeat (k) @(negedge clk);

        do_reset;     // reset hits while the handler is running

        // everything the trap machinery owns must be back at its reset value
        if (top_inst.PC_IF !== 32'd0)                    begin bad = bad + 1; $display("  [FAIL] reset-in-handler kind=%0d N=%0d k=%0d: PC_IF = %0d after reset", kind, N, k, top_inst.PC_IF); end
        if (top_inst.mie_val !== 1'b0)                   begin bad = bad + 1; $display("  [FAIL] reset-in-handler kind=%0d N=%0d k=%0d: MIE = %b after reset", kind, N, k, top_inst.mie_val); end
        if (top_inst.mpie_val !== 1'b0)                  begin bad = bad + 1; $display("  [FAIL] reset-in-handler kind=%0d N=%0d k=%0d: MPIE = %b after reset", kind, N, k, top_inst.mpie_val); end
        if (top_inst.current_priority_val !== 2'd0)      begin bad = bad + 1; $display("  [FAIL] reset-in-handler kind=%0d N=%0d k=%0d: current_priority = %0d after reset", kind, N, k, top_inst.current_priority_val); end
        if (top_inst.previous_priority_val !== 2'd0)     begin bad = bad + 1; $display("  [FAIL] reset-in-handler kind=%0d N=%0d k=%0d: previous_priority = %0d after reset", kind, N, k, top_inst.previous_priority_val); end
        if (top_inst.pending_keyboard || top_inst.pending_disk)
                                                         begin bad = bad + 1; $display("  [FAIL] reset-in-handler kind=%0d N=%0d k=%0d: pending bit survived reset (kbd=%b disk=%b)", kind, N, k, top_inst.pending_keyboard, top_inst.pending_disk); end
        if (top_inst.mepc_val !== 32'd0)                 begin bad = bad + 1; $display("  [FAIL] reset-in-handler kind=%0d N=%0d k=%0d: mepc = 0x%0h after reset", kind, N, k, top_inst.mepc_val); end
        if (top_inst.mcause_val !== 32'd0)               begin bad = bad + 1; $display("  [FAIL] reset-in-handler kind=%0d N=%0d k=%0d: mcause = 0x%0h after reset", kind, N, k, top_inst.mcause_val); end
        if (top_inst.mtval_val !== 32'd0)                begin bad = bad + 1; $display("  [FAIL] reset-in-handler kind=%0d N=%0d k=%0d: mtval = 0x%0h after reset", kind, N, k, top_inst.mtval_val); end
        if (top_inst.mtvec_val !== 32'd101)              begin bad = bad + 1; $display("  [FAIL] reset-in-handler kind=%0d N=%0d k=%0d: mtvec = 0x%0h after reset, expected 0x65", kind, N, k, top_inst.mtvec_val); end
        if (top_inst.mie_csr_val !== 32'd0)              begin bad = bad + 1; $display("  [FAIL] reset-in-handler kind=%0d N=%0d k=%0d: mie csr = 0x%0h after reset", kind, N, k, top_inst.mie_csr_val); end
        if (top_inst.mscratch_val !== 32'd0)             begin bad = bad + 1; $display("  [FAIL] reset-in-handler kind=%0d N=%0d k=%0d: mscratch = 0x%0h after reset", kind, N, k, top_inst.mscratch_val); end
        if (top_inst.interrupt_taken !== 1'b0)           begin bad = bad + 1; $display("  [FAIL] reset-in-handler kind=%0d N=%0d k=%0d: interrupt_taken high after reset", kind, N, k); end

        errors = errors + bad;

        // the whole program again from scratch, no interrupt: must equal the reference run
        run_to_end(0, -1);
        compare_to_ref(0, kind, N);
    end
endtask

// ---------------- main ----------------
integer kind, N, k, ni, p, gi, a;
integer exp_traps;
integer cov_total, cov_hit, cov_listed;
reg [31:0] wv;

initial begin
    reset = 1'b1;
    interrupt_keyboard = 1'b0;
    interrupt_disk     = 1'b0;
    errors = 0; warnings = 0; prints = 0; runs = 0; bad_runs = 0;
    irq_cnt = 0; exc_cnt = 0; first_trap_pc = -1;
    cyc = 0; hang = 1'b0; rec_ref = 1'b0;
    for (p = 0; p < 1024; p = p + 1) begin ref_exec[p] = 1'b0; hit_int[p] = 1'b0; end

    #23;

    // ================= Part 1: reference run =================
    $display("--- Part 1: reference run (no interrupt) ---");
    do_reset;
    rec_ref = 1'b1;
    run_to_end(0, -1);
    rec_ref = 1'b0;
    ref_cycles = cyc;

    for (p = 0; p < 32; p = p + 1)          ref_reg[p] = snap_reg[p];
    for (p = 0; p < DMEM_BYTES; p = p + 1)  ref_mem[p] = snap_mem[p];
    ref_mscratch = snap_mscratch; ref_mie_csr = snap_mie_csr; ref_mtvec = snap_mtvec;
    ref_mie = snap_mie; ref_mpie = snap_mpie; ref_cprio = snap_cprio;

    if (hang) begin
        errors = errors + 1;
        $display("  [FAIL] reference run hung (x30=%0d PC_IF=%0d)", snap_reg[30], top_inst.PC_IF);
    end
    $display("  reference run reached the end marker after %0d cycles", ref_cycles);

    if (irq_cnt !== 0 || exc_cnt !== 0) begin
        errors = errors + 1;
        $display("  [FAIL] reference run took %0d interrupts and %0d exceptions, expected none", irq_cnt, exc_cnt);
    end

    for (gi = 0; gi < `IM.n_greg; gi = gi + 1) begin
        if (snap_reg[`IM.gold_reg[gi]] !== `IM.gold_rval[gi]) begin
            errors = errors + 1;
            $display("  [FAIL] golden %0s: x%0d = 0x%0h, expected 0x%0h",
                     `IM.gold_rname[gi], `IM.gold_reg[gi], snap_reg[`IM.gold_reg[gi]], `IM.gold_rval[gi]);
        end
    end
    for (gi = 0; gi < `IM.n_gmem; gi = gi + 1) begin
        a  = `IM.gold_addr[gi];
        wv = {snap_mem[a+3], snap_mem[a+2], snap_mem[a+1], snap_mem[a]};
        if (wv !== `IM.gold_mval[gi]) begin
            errors = errors + 1;
            $display("  [FAIL] golden data mem[%0d] = 0x%0h, expected 0x%0h", a, wv, `IM.gold_mval[gi]);
        end
    end
    if (ref_mie !== 1'b1)   begin errors = errors + 1; $display("  [FAIL] reference run: final MIE = %b, expected 1", ref_mie); end
    if (ref_cprio !== 2'd0) begin errors = errors + 1; $display("  [FAIL] reference run: final current_priority = %0d, expected 0", ref_cprio); end
    if (errors == 0) $display("  [ ok ] reference run matches all %0d register and %0d memory expectations", `IM.n_greg, `IM.n_gmem);

    // ================= Part 2: the sweep =================
    $display("--- Part 2: sweep, kinds 1..3, N = 0..%0d ---", ref_cycles + EXTRA);
    for (kind = 1; kind <= 3; kind = kind + 1) begin
        exp_traps = (kind == 3) ? 2 : 1;      // both at once: disk first, keyboard right after disk's mret
        for (N = 0; N <= ref_cycles + EXTRA; N = N + 1) begin
            do_reset;
            run_to_end(kind, N);
            compare_to_ref(exp_traps, kind, N);
        end
        $display("  kind %0d done (%0d runs so far, %0d with failures)", kind, runs, bad_runs);
    end

    // which instructions did an interrupt actually land on?
    cov_total = 0; cov_hit = 0; cov_listed = 0;
    for (p = 0; p < 1024; p = p + 1)
        if (ref_exec[p]) begin
            cov_total = cov_total + 1;
            if (hit_int[p]) cov_hit = cov_hit + 1;
        end
    $display("  coverage: an interrupt was taken on %0d of the %0d instruction addresses the program executes", cov_hit, cov_total);
    for (p = 0; p < 1024; p = p + 1)
        if (ref_exec[p] && !hit_int[p] && cov_listed < 40) begin
            $display("    never interrupted: pc %0d (expected for the boot jal, the first CSR setup and the MIE=0 window before the software mret)", p*4);
            cov_listed = cov_listed + 1;
        end

    // ================= Part 3: reset in the middle of a handler =================
    $display("--- Part 3: reset while the handler is running ---");
    for (kind = 1; kind <= 3; kind = kind + 1)
        for (ni = 0; ni < 3; ni = ni + 1) begin
            N = (ni == 0) ? 40 : (ni == 1) ? ref_cycles / 3 : (2 * ref_cycles) / 3;
            for (k = 0; k <= 14; k = k + 1)
                run_mid_reset(kind, N, k);
        end
    $display("  reset-in-handler cases done");

    $display("---FINAL---");
    $display("  %0d runs, %0d with failures, %0d failed checks in total", runs, bad_runs, errors);
    if (prints >= MAXPRINT) $display("  (only the first %0d failing runs were printed in detail)", MAXPRINT);
    if (errors == 0) $display("=== ALL CHECKS PASSED ===");
    else             $display("=== %0d CHECK(S) FAILED ===", errors);
    $finish;
end

// ---------------- watchdog ----------------
initial begin
    #2000000000;
    $display("---WATCHDOG FIRED: sweep did not finish---");
    $display("=== %0d CHECK(S) FAILED (hang) ===", errors + 1);
    $finish;
end

`ifdef DUMP
initial begin
    $dumpfile("waves_sweep.vcd");
    $dumpvars(0, top_inst);
end
`endif

endmodule