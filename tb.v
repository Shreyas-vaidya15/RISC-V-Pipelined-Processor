`timescale 1ns/1ps

// ============================================================================================
// INTERRUPT SWEEP TESTBENCH, stage 4: AHB-Lite with wait states AND bus errors.  DUT = soc_top (CPU + AHB data slave).
// Pairs with the stage 4 "INTERRUPT SWEEP IMAGE" instruction_memory.v (section S8 takes 11 bus errors on purpose).
//
// Build (leave out any other testbench):
//   iverilog -s tb_sweep -o sim_sweep <all .v files, one testbench only>
//   vvp sim_sweep
//
// The whole test (parts 1-3b) is run once per WAIT MODE:
//   mode 0  no wait states
//   mode 1  every transfer waits 1 cycle
//   mode 2  every transfer waits 2 cycles
//   mode 3  a fixed pseudo-random 0..3 waits per transfer (depends only on the cycle number)
//
// Part 1   reference run: no interrupt. Checked against the image's golden tables (gr / gm), against exp_exc (all exceptions the
//          program takes) and exp_hold (older-transfer holds that the operand-capture cases must cause). Final state saved.
// Part 2   sweep: kind (keyboard, disk, both) x injection cycle N = 0 .. ref_cycles+8: reset, ONE 1-cycle pulse at
//          cycle N, run to the end marker, drain, compare against the reference run (only x23 may differ).
//          The number of exceptions must equal the reference run's. Also: at least once an interrupt must have been
//          ready to fire in the very cycle of a bus error (the bus error must win).
// Part 3   reset in the middle of an interrupt handler.
// Part 3b  reset while the slave answers with ERROR (k = 0..5 cycles after the response starts), several error responses.
//
// Always running (every cycle of every run):
//   AHB hold monitor: if HREADY was low in the previous cycle, HADDR / HTRANS / HWRITE / HSIZE / HWDATA must be unchanged,
//                     with ONE exception: in the last cycle of an ERROR response (HRESP=1, HREADY=1) HTRANS may change to IDLE.
//   Bus error monitor: in every bus error cycle HTRANS = IDLE, no register write, no interrupt / other exception in that cycle,
//                      slave in ERR2; next cycle mepc / mcause / mtval hold the right values for the faulting load/store.
//
// The register file and data memory have no reset in the RTL, so this testbench clears them (hierarchically)
// every time it resets.
// ============================================================================================

module tb_sweep();

localparam DMEM_BYTES = 256;      // data_memory DEPTH (64 words) * 4
localparam LIMIT      = 8000;     // cycle limit for one run (hang detection)
localparam DRAIN      = 40;       // cycles to keep running after the end marker
localparam EXTRA      = 8;        // sweep this many cycles past the reference end
localparam MAXPRINT   = 40;       // max failing runs / checks printed in detail
localparam OLD_REF_CYCLES = 0;    // 0 = do not check the 0-wait reference length. S9 changed it: run once, then put the mode 0 number here
localparam NUM_MODES  = 4;

reg clk, reset, interrupt_keyboard, interrupt_disk;
reg [3:0] wait_cycles;
integer wait_mode;
integer cyc;

soc_top soc_inst (
    .clk(clk),
    .reset(reset),
    .interrupt_keyboard(interrupt_keyboard),
    .interrupt_disk(interrupt_disk),
    .WAIT_CYCLES(wait_cycles)
);

// 4 KB of instruction memory (DEPTH is in words); also moves the instruction_access_fault limit
defparam soc_inst.cpu_inst.IF_stage_inst.DEPTH = 1024;

`define CPU     soc_inst.cpu_inst
`define SLAVE   soc_inst.data_slave_inst
`define IM      soc_inst.cpu_inst.IF_stage_inst.instruction_memory_inst
`define REG(n)  soc_inst.cpu_inst.ID_stage_inst.register_file_inst.registers[n]
`define DMEM(i) soc_inst.data_slave_inst.data_memory_inst.mem[i]

initial clk = 1'b0;
always #5 clk = ~clk;

// ---------------- wait generator: how many wait states the slave gives the next accepted transfer ----------------
always @(*) begin
    case (wait_mode)
        0:       wait_cycles = 4'd0;
        1:       wait_cycles = 4'd1;
        2:       wait_cycles = 4'd2;
        default: wait_cycles = ((cyc * 13) ^ (cyc >> 1)) & 3;     // pseudo-random 0..3, fixed per cycle number
    endcase
end

// ---------------- bookkeeping ----------------
integer errors, warnings, prints;
integer irq_cnt, exc_cnt, first_trap_pc;
integer ref_cycles, ref0_cycles, ref_exc;
integer runs, bad_runs, mode_runs0, mode_bad0;
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
reg ref_allow[0:1023];            // word PCs that had at least one cycle in EX where an interrupt was ALLOWED (everything but 'pending')
integer hold_cnt;                 // ex_hold cycles in the reference run
reg hit_int  [0:1023];            // word PCs that an interrupt was actually taken on (mepc)

// ---------------- trap monitor (negedge) ----------------
always @(negedge clk) begin
    if (!reset) begin
        if (`CPU.interrupt_taken) begin
            irq_cnt = irq_cnt + 1;
            if (irq_cnt == 1) first_trap_pc = `CPU.PC_EX;
            hit_int[`CPU.PC_EX[11:2]] = 1'b1;
        end
        if (`CPU.exception_taken)
            exc_cnt = exc_cnt + 1;
        if (rec_ref && `CPU.Valid_EX && `CPU.HREADY)
            ref_exec[`CPU.PC_EX[11:2]] = 1'b1;
        // same conditions as interrupt_taken in top.v, minus 'someone is pending'
        if (rec_ref && `CPU.Valid_EX && `CPU.mie_val && `CPU.mie_csr_val[11] && !`CPU.Mret_EX && `CPU.HREADY && !`CPU.bus_error && !`CPU.mem_transfer_MEM)
            ref_allow[`CPU.PC_EX[11:2]] = 1'b1;
        if (rec_ref && `CPU.ex_hold)
            hold_cnt = hold_cnt + 1;
    end
end

// ---------------- AHB hold monitor (negedge) ----------------
// If HREADY was low in the previous cycle, nothing the master drives may change in this cycle.
// The one allowed change: HTRANS goes to IDLE in the last cycle of an ERROR response (HRESP = 1, HREADY = 1).
reg [31:0] pv_haddr, pv_hwdata;
reg [1:0]  pv_htrans;
reg [2:0]  pv_hsize;
reg        pv_hwrite, pv_hready, pv_valid;
reg        same_other, same_all, cancel_ok;
integer    proto_prints;
initial begin pv_valid = 1'b0; proto_prints = 0; end

always @(negedge clk) begin
    if (reset) pv_valid = 1'b0;
    else begin
        if (pv_valid && !pv_hready) begin
            same_other = (`CPU.HADDR === pv_haddr) && (`CPU.HWRITE === pv_hwrite) &&
                         (`CPU.HSIZE === pv_hsize)  && (`CPU.HWDATA === pv_hwdata);
            same_all   = same_other && (`CPU.HTRANS === pv_htrans);
            cancel_ok  = same_other && (`CPU.HRESP === 1'b1) && (`CPU.HREADY === 1'b1) && (`CPU.HTRANS === 2'b00);
            if (!same_all && !cancel_ok) begin
                errors = errors + 1;
                if (proto_prints < 20)
                    $display("  [FAIL] mode=%0d: bus signal changed while HREADY was low (HADDR %0h->%0h HTRANS %0b->%0b HWRITE %b->%b HWDATA %0h->%0h)",
                             wait_mode, pv_haddr, `CPU.HADDR, pv_htrans, `CPU.HTRANS, pv_hwrite, `CPU.HWRITE, pv_hwdata, `CPU.HWDATA);
                proto_prints = proto_prints + 1;
            end
        end
        pv_haddr  = `CPU.HADDR;
        pv_hwdata = `CPU.HWDATA;
        pv_htrans = `CPU.HTRANS;
        pv_hsize  = `CPU.HSIZE;
        pv_hwrite = `CPU.HWRITE;
        pv_hready = `CPU.HREADY;
        pv_valid  = 1'b1;
    end
end

// ---------------- bus error monitor (negedge) ----------------
// In the last cycle of an ERROR response (bus_error = 1):
//   HTRANS must be IDLE, the register file write enable must be low, no interrupt and no other exception may be taken
//   in the same cycle, and the slave must be in ERR2.
// In the next cycle mepc / mcause / mtval must hold: PC of the faulting load/store, cause 5 (load) or 7 (store), the bad address.
// The faulting PC is also looked up in the instruction image: it must really be a load (cause 5) or a store (cause 7),
// and the bad address must be outside data memory.
reg        be_pending;
reg [31:0] be_exp_mepc, be_exp_mtval, be_exp_cause;
reg [6:0]  be_opc;
integer    be_prints, both_cnt;
initial begin be_pending = 1'b0; be_prints = 0; both_cnt = 0; end

always @(negedge clk) begin
    if (reset) be_pending = 1'b0;
    else begin
        // the trap of the previous cycle has been written into the CSRs by now
        if (be_pending) begin
            if (`CPU.mepc_val !== be_exp_mepc || `CPU.mcause_val !== be_exp_cause || `CPU.mtval_val !== be_exp_mtval) begin
                errors = errors + 1;
                if (be_prints < 20)
                    $display("  [FAIL] mode=%0d: after a bus error mepc/mcause/mtval = 0x%0h/0x%0h/0x%0h, expected 0x%0h/0x%0h/0x%0h",
                             wait_mode, `CPU.mepc_val, `CPU.mcause_val, `CPU.mtval_val, be_exp_mepc, be_exp_cause, be_exp_mtval);
                be_prints = be_prints + 1;
            end
            be_pending = 1'b0;
        end

        if (`CPU.bus_error === 1'b1) begin
            be_exp_mepc  = `CPU.PCPlus4_WB - 32'd4;
            be_exp_mtval = `CPU.ALUResult_WB;
            be_exp_cause = `CPU.IsLoad_WB ? 32'd5 : 32'd7;
            be_opc       = `IM.mem[be_exp_mepc][6:0];
            be_pending   = 1'b1;

            if (`CPU.HTRANS !== 2'b00 || `CPU.ID_stage_inst.we !== 1'b0 || `CPU.interrupt_taken !== 1'b0 ||
                `CPU.exception_taken_EX !== 1'b0 || `CPU.exception_taken_ID !== 1'b0 || `SLAVE.state !== 2'd3) begin
                errors = errors + 1;
                if (be_prints < 20)
                    $display("  [FAIL] mode=%0d: bus error cycle: HTRANS=%b regwrite=%b int_taken=%b exc_EX=%b exc_ID=%b slave state=%0d (expected 00 0 0 0 0 3)",
                             wait_mode, `CPU.HTRANS, `CPU.ID_stage_inst.we, `CPU.interrupt_taken, `CPU.exception_taken_EX,
                             `CPU.exception_taken_ID, `SLAVE.state);
                be_prints = be_prints + 1;
            end

            if (!((be_opc === 7'b0000011 && be_exp_cause === 32'd5) || (be_opc === 7'b0100011 && be_exp_cause === 32'd7))) begin
                errors = errors + 1;
                if (be_prints < 20)
                    $display("  [FAIL] mode=%0d: bus error with cause %0d but the instruction at mepc 0x%0h has opcode %b (not the matching load/store)",
                             wait_mode, be_exp_cause, be_exp_mepc, be_opc);
                be_prints = be_prints + 1;
            end

            if ((be_exp_mtval >= DMEM_BYTES) !== 1'b1) begin
                errors = errors + 1;
                if (be_prints < 20)
                    $display("  [FAIL] mode=%0d: bus error for address 0x%0h, which is inside data memory", wait_mode, be_exp_mtval);
                be_prints = be_prints + 1;
            end

            // an interrupt that would have been taken in this very cycle (bus error wins, the interrupt waits)
            if (`CPU.mie_val && `CPU.mie_csr_val[11] && `CPU.priority_ok && !`CPU.EX_is_bubble && !`CPU.Mret_EX)
                both_cnt = both_cnt + 1;
        end
    end
end

// ---------------- reset to a fresh state ----------------
// do_reset_now: call at a negedge. Returns with reset still asserted, at a negedge, after two clock edges with reset high.
// do_reset:     waits for the next negedge first.
task do_reset_now;
    integer j;
    begin
        reset = 1'b1;
        interrupt_keyboard = 1'b0;
        interrupt_disk     = 1'b0;
        for (j = 0; j < 32; j = j + 1)          `REG(j)  = 32'b0;
        for (j = 0; j < DMEM_BYTES; j = j + 1)  `DMEM(j) = 8'h00;
        irq_cnt = 0; exc_cnt = 0; first_trap_pc = -1;
        cyc = 0;
        @(negedge clk);
        @(negedge clk);
    end
endtask

task do_reset;
    begin
        @(negedge clk);
        do_reset_now;
    end
endtask

// ---------------- snapshot of the final state ----------------
task take_snapshot;
    integer j;
    begin
        for (j = 0; j < 32; j = j + 1)          snap_reg[j] = `REG(j);
        for (j = 0; j < DMEM_BYTES; j = j + 1)  snap_mem[j] = `DMEM(j);
        snap_mscratch = `CPU.mscratch_val;
        snap_mie_csr  = `CPU.mie_csr_val;
        snap_mtvec    = `CPU.mtvec_val;
        snap_mie      = `CPU.mie_val;
        snap_mpie     = `CPU.mpie_val;
        snap_cprio    = `CPU.current_priority_val;
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
// (kind 9 = the rerun after a reset in an error response, N = occurrence*100 + k)
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
                                            kind, N, snap_reg[30], `CPU.PC_IF);
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
        // the exceptions are the program's own bus errors: an interrupt must not add, hide or repeat any of them
        if (exc_cnt !== ref_exc) begin
            bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: %0d exception(s) taken, reference run took %0d (first interrupt on mepc=%0d)",
                                            kind, N, exc_cnt, ref_exc, first_trap_pc);
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

        if (`CPU.pending_keyboard || `CPU.pending_disk) begin
            bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: interrupt still pending at the end (kbd=%b disk=%b)",
                                            kind, N, `CPU.pending_keyboard, `CPU.pending_disk);
        end

        // after the drain no transfer may be in flight and the slave must be idle and ready
        if (`CPU.HTRANS !== 2'b00) begin
            bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: HTRANS = %b at the end, expected IDLE", kind, N, `CPU.HTRANS);
        end
        if (`CPU.HREADY !== 1'b1) begin
            bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: HREADY low at the end", kind, N);
        end
        if (`SLAVE.state !== 2'd0 || `SLAVE.HRESP !== 1'b0) begin
            bad = bad + 1;
            if (prints < MAXPRINT) $display("  [FAIL] kind=%0d N=%0d: slave not idle at the end (state=%0d HRESP=%b)", kind, N, `SLAVE.state, `SLAVE.HRESP);
        end

        runs = runs + 1;
        if (bad != 0) begin
            bad_runs = bad_runs + 1;
            errors   = errors + bad;
            prints   = prints + 1;
        end
    end
endtask

// ---------------- state right after a reset (CPU trap state + slave state) ----------------
// Call with reset still asserted. Result in rs_bad. rs_tag only changes the text of the messages.
integer rs_bad;
reg [8*12-1:0] rs_tag;

task rs_fail;
    input integer kind;
    input integer N;
    input integer k;
    input [8*24-1:0] what;
    input [31:0] val;
    begin
        rs_bad = rs_bad + 1;
        $display("  [FAIL] reset-%0s kind=%0d N=%0d k=%0d: %0s = 0x%0h after reset", rs_tag, kind, N, k, what, val);
    end
endtask

task check_reset_state;
    input integer kind;
    input integer N;
    input integer k;
    begin
        rs_bad = 0;
        if (`CPU.PC_IF !== 32'd0)                    rs_fail(kind, N, k, "PC_IF", `CPU.PC_IF);
        if (`CPU.mie_val !== 1'b0)                   rs_fail(kind, N, k, "MIE", `CPU.mie_val);
        if (`CPU.mpie_val !== 1'b0)                  rs_fail(kind, N, k, "MPIE", `CPU.mpie_val);
        if (`CPU.current_priority_val !== 2'd0)      rs_fail(kind, N, k, "current_priority", `CPU.current_priority_val);
        if (`CPU.previous_priority_val !== 2'd0)     rs_fail(kind, N, k, "previous_priority", `CPU.previous_priority_val);
        if (`CPU.pending_keyboard !== 1'b0)          rs_fail(kind, N, k, "pending_keyboard", `CPU.pending_keyboard);
        if (`CPU.pending_disk !== 1'b0)              rs_fail(kind, N, k, "pending_disk", `CPU.pending_disk);
        if (`CPU.mepc_val !== 32'd0)                 rs_fail(kind, N, k, "mepc", `CPU.mepc_val);
        if (`CPU.mcause_val !== 32'd0)               rs_fail(kind, N, k, "mcause", `CPU.mcause_val);
        if (`CPU.mtval_val !== 32'd0)                rs_fail(kind, N, k, "mtval", `CPU.mtval_val);
        if (`CPU.mtvec_val !== 32'd101)              rs_fail(kind, N, k, "mtvec (expected 0x65)", `CPU.mtvec_val);
        if (`CPU.mie_csr_val !== 32'd0)              rs_fail(kind, N, k, "mie csr", `CPU.mie_csr_val);
        if (`CPU.mscratch_val !== 32'd0)             rs_fail(kind, N, k, "mscratch", `CPU.mscratch_val);
        if (`CPU.interrupt_taken !== 1'b0)           rs_fail(kind, N, k, "interrupt_taken", `CPU.interrupt_taken);
        if (`CPU.bus_error !== 1'b0)                 rs_fail(kind, N, k, "bus_error", `CPU.bus_error);
        if (`CPU.HTRANS !== 2'b00)                   rs_fail(kind, N, k, "HTRANS", `CPU.HTRANS);

        // AHB slave: FSM idle, saved address phase gone, no error pending, no wait pending, ready
        if (`SLAVE.state !== 2'd0)                   rs_fail(kind, N, k, "slave state", `SLAVE.state);
        if (`SLAVE.bad_dp !== 1'b0)                  rs_fail(kind, N, k, "slave bad_dp", `SLAVE.bad_dp);
        if (`SLAVE.valid_dp !== 1'b0)                rs_fail(kind, N, k, "slave valid_dp", `SLAVE.valid_dp);
        if (`SLAVE.write_dp !== 1'b0)                rs_fail(kind, N, k, "slave write_dp", `SLAVE.write_dp);
        if (`SLAVE.wait_cnt !== 4'd0)                rs_fail(kind, N, k, "slave wait_cnt", `SLAVE.wait_cnt);
        if (`SLAVE.HRESP !== 1'b0)                   rs_fail(kind, N, k, "slave HRESP", `SLAVE.HRESP);
        if (`SLAVE.HREADYOUT !== 1'b1)               rs_fail(kind, N, k, "slave HREADYOUT (expected 1)", `SLAVE.HREADYOUT);
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
            if (`CPU.interrupt_taken) got = 1'b1;
        end
        interrupt_keyboard = 1'b0;
        interrupt_disk     = 1'b0;

        if (!got) begin
            bad = bad + 1;
            $display("  [FAIL] reset-in-handler kind=%0d N=%0d: interrupt never taken", kind, N);
        end

        repeat (k) @(negedge clk);

        do_reset;     // reset hits while the handler is running (possibly while the slave is waiting)

        rs_tag = "in-handler";
        check_reset_state(kind, N, k);
        errors = errors + bad + rs_bad;

        // the whole program again from scratch, no interrupt: must equal the reference run
        run_to_end(0, -1);
        compare_to_ref(0, kind, N);
    end
endtask

// ---------------- reset-in-error-response: one case ----------------
// Run with no interrupt until the occ-th ERROR response starts (slave in ERR1, the first error cycle).
// Reset k cycles later (k = 0: during ERR1, k = 1: during ERR2, then the trap and handler start), check the reset state
// (CPU and slave), then run the whole program again and compare with the reference run.
task run_err_reset;
    input integer occ;
    input integer k;
    reg got;
    integer seen, bad;
    begin
        bad = 0;
        do_reset;
        reset = 1'b0;
        cyc = 0;
        got = 1'b0;
        seen = 0;
        while (!got && cyc < LIMIT) begin
            @(negedge clk);
            cyc = cyc + 1;
            if (`SLAVE.state == 2'd2) seen = seen + 1;     // ERR1 lasts one cycle per error response
            if (seen == occ) got = 1'b1;
        end

        if (!got) begin
            bad = bad + 1;
            $display("  [FAIL] reset-in-error occ=%0d k=%0d: error response number %0d never started", occ, k, occ);
        end

        repeat (k) @(negedge clk);

        do_reset_now;     // we are at a negedge already: reset hits right now, in the middle of the error response

        rs_tag = "in-error";
        check_reset_state(0, occ, k);
        errors = errors + bad + rs_bad;

        run_to_end(0, -1);
        compare_to_ref(0, 9, occ * 100 + k);
    end
endtask

// ---------------- the parts, for one wait mode ----------------
integer kind, N, k, ni, oi, occ, p, gi, a;
integer exp_traps, e0;
integer cov_total, cov_hit, cov_listed, cov_allowed, cov_holes;
reg [31:0] wv;

task do_mode;
    input integer mode;
    begin
        wait_mode = mode;
        mode_runs0 = runs; mode_bad0 = bad_runs;
        for (p = 0; p < 1024; p = p + 1) begin ref_exec[p] = 1'b0; ref_allow[p] = 1'b0; hit_int[p] = 1'b0; end
        hold_cnt = 0;

        $display("=================== wait mode %0d (%0s) ===================", mode,
                 (mode == 0) ? "no waits" : (mode == 1) ? "1 wait per transfer" : (mode == 2) ? "2 waits per transfer" : "pseudo-random 0..3 waits");

        // ================= Part 1: reference run =================
        $display("--- Part 1: reference run (no interrupt) ---");
        e0 = errors;
        do_reset;
        rec_ref = 1'b1;
        run_to_end(0, -1);
        rec_ref = 1'b0;
        ref_cycles = cyc;
        ref_exc = exc_cnt;
        if (mode == 0) ref0_cycles = cyc;

        for (p = 0; p < 32; p = p + 1)          ref_reg[p] = snap_reg[p];
        for (p = 0; p < DMEM_BYTES; p = p + 1)  ref_mem[p] = snap_mem[p];
        ref_mscratch = snap_mscratch; ref_mie_csr = snap_mie_csr; ref_mtvec = snap_mtvec;
        ref_mie = snap_mie; ref_mpie = snap_mpie; ref_cprio = snap_cprio;

        if (hang) begin
            errors = errors + 1;
            $display("  [FAIL] reference run hung (x30=%0d PC_IF=%0d)", snap_reg[30], `CPU.PC_IF);
        end
        $display("  reference run reached the end marker after %0d cycles, %0d exceptions, %0d older-transfer holds", ref_cycles, ref_exc, hold_cnt);

        if (mode == 0) begin
            if (OLD_REF_CYCLES != 0) begin
                if (ref_cycles !== OLD_REF_CYCLES) begin
                    errors = errors + 1;
                    $display("  [FAIL] 0-wait reference run took %0d cycles, expected %0d", ref_cycles, OLD_REF_CYCLES);
                end
                else
                    $display("  [ ok ] 0-wait cycle count as expected (%0d)", ref_cycles);
            end
        end
        else begin
            if (ref_cycles <= ref0_cycles) begin
                errors = errors + 1;
                $display("  [FAIL] with waits the run took %0d cycles, not more than the 0-wait run (%0d): waits had no effect", ref_cycles, ref0_cycles);
            end
            else
                $display("  [ ok ] waits lengthened the run: %0d cycles vs %0d with no waits", ref_cycles, ref0_cycles);
        end

        if (irq_cnt !== 0 || exc_cnt !== `IM.exp_exc) begin
            errors = errors + 1;
            $display("  [FAIL] reference run took %0d interrupts and %0d exceptions, expected 0 and %0d", irq_cnt, exc_cnt, `IM.exp_exc);
        end

        if (hold_cnt < `IM.exp_hold) begin
            errors = errors + 1;
            $display("  [FAIL] only %0d older-transfer holds (ex_hold) in the reference run, the image needs at least %0d: the operand-capture cases did not reach the hold", hold_cnt, `IM.exp_hold);
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
        if (ref_mpie !== 1'b1)  begin errors = errors + 1; $display("  [FAIL] reference run: final MPIE = %b, expected 1", ref_mpie); end
        if (ref_cprio !== 2'd0) begin errors = errors + 1; $display("  [FAIL] reference run: final current_priority = %0d, expected 0", ref_cprio); end
        if (errors == e0) $display("  [ ok ] reference run matches all %0d register and %0d memory expectations", `IM.n_greg, `IM.n_gmem);

        // ================= Part 2: the sweep =================
        $display("--- Part 2: sweep, kinds 1..3, N = 0..%0d ---", ref_cycles + EXTRA);
        both_cnt = 0;
        for (kind = 1; kind <= 3; kind = kind + 1) begin
            exp_traps = (kind == 3) ? 2 : 1;      // both at once: disk first, keyboard right after disk's mret
            for (N = 0; N <= ref_cycles + EXTRA; N = N + 1) begin
                do_reset;
                run_to_end(kind, N);
                compare_to_ref(exp_traps, kind, N);
            end
            $display("  kind %0d done (%0d runs so far in this mode, %0d with failures)", kind, runs - mode_runs0, bad_runs - mode_bad0);
        end

        if (both_cnt == 0) begin
            errors = errors + 1;
            $display("  [FAIL] an interrupt was never ready to fire in the same cycle as a bus error: that case was not exercised");
        end
        else
            $display("  [ ok ] interrupt ready in the same cycle as a bus error (bus error won): %0d times", both_cnt);

        // which instructions did an interrupt actually land on?
        // allowed = at some cycle with this instruction in EX the interrupt gate was open (MIE, mie[11], no mret, bus ready, no bus error,
        //           no load/store in MEM). Every allowed address MUST have been hit by the sweep: a miss is a hole.
        // Addresses that were never allowed are blocked by design (before MIE is on, MIE = 0 windows, behind a load/store, mret).
        cov_total = 0; cov_hit = 0; cov_listed = 0; cov_allowed = 0; cov_holes = 0;
        for (p = 0; p < 1024; p = p + 1)
            if (ref_exec[p] && !(p == 25 || (p >= 48 && p < 56))) begin   // exception handler (pc 100, 192..220) runs with MIE = 0
                cov_total = cov_total + 1;
                if (ref_allow[p]) cov_allowed = cov_allowed + 1;
                if (hit_int[p])   cov_hit = cov_hit + 1;
                if (ref_allow[p] && !hit_int[p]) begin
                    cov_holes = cov_holes + 1;
                    if (cov_listed < 40) begin
                        $display("    HOLE: allowed but never interrupted: pc %0d", p*4);
                        cov_listed = cov_listed + 1;
                    end
                end
            end
        $display("  coverage: %0d instruction addresses executed, %0d were open to an interrupt, an interrupt landed on %0d, %0d blocked by design, %0d holes",
                 cov_total, cov_allowed, cov_hit, cov_total - cov_allowed, cov_holes);
        if (cov_holes != 0) begin
            errors = errors + 1;
            $display("  [FAIL] %0d address(es) were open to an interrupt but the sweep never landed one there", cov_holes);
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

        // ================= Part 3b: reset in the middle of an ERROR response =================
        $display("--- Part 3b: reset while the slave answers with ERROR ---");
        for (oi = 0; oi < 3; oi = oi + 1) begin
            occ = (oi == 0) ? 1 : (oi == 1) ? 6 : `IM.exp_bus_err;     // first, a middle and the last error response
            for (k = 0; k <= 5; k = k + 1)
                run_err_reset(occ, k);
        end
        $display("  reset-in-error cases done");

        $display("  mode %0d: %0d runs, %0d with failures", mode, runs - mode_runs0, bad_runs - mode_bad0);
    end
endtask

// ---------------- main ----------------
integer m;

initial begin
    reset = 1'b1;
    interrupt_keyboard = 1'b0;
    interrupt_disk     = 1'b0;
    wait_mode = 0;
    errors = 0; warnings = 0; prints = 0; runs = 0; bad_runs = 0;
    irq_cnt = 0; exc_cnt = 0; first_trap_pc = -1;
    cyc = 0; hang = 1'b0; rec_ref = 1'b0; ref0_cycles = 0; ref_exc = 0;
    rs_bad = 0; rs_tag = "";

    #23;

    for (m = 0; m < NUM_MODES; m = m + 1)
        do_mode(m);

    $display("---FINAL---");
    $display("  %0d runs, %0d with failures, %0d failed checks in total", runs, bad_runs, errors);
    if (prints >= MAXPRINT) $display("  (only the first %0d failing runs were printed in detail)", MAXPRINT);
    if (errors == 0) $display("=== ALL CHECKS PASSED ===");
    else             $display("=== %0d CHECK(S) FAILED ===", errors);
    $finish;
end

// ---------------- watchdog ----------------
initial begin
    #5000000000;
    $display("---WATCHDOG FIRED: sweep did not finish---");
    $display("=== %0d CHECK(S) FAILED (hang) ===", errors + 1);
    $finish;
end

`ifdef DUMP
initial begin
    $dumpfile("waves_sweep.vcd");
    $dumpvars(0, soc_inst);
    $dumpvars(0, wait_cycles, wait_mode);
end
`endif

endmodule