module tb();

reg clk, reset, interrupt_keyboard, interrupt_disk;

top top_inst (
    .clk(clk),
    .reset(reset),
    .interrupt_keyboard(interrupt_keyboard),
    .interrupt_disk(interrupt_disk)
);

always #5 clk = ~clk;

// ---- watchdog: if the main sequence ever hangs on a wait(), don't let the sim run forever ----
initial begin
    #6000;
    $display("---WATCHDOG FIRED: a wait() never resolved, main sequence stuck---");
    $display("x2(sp)=%0d x30=%0d PC_EX=%0d mepc=%0d mcause=%0d",
        top_inst.ID_stage_inst.register_file_inst.registers[2],
        top_inst.ID_stage_inst.register_file_inst.registers[30],
        top_inst.PC_EX, top_inst.mepc_val, top_inst.mcause_val);
    $finish;
end

initial begin
    reset = 1'b1;
    clk = 1'b0;
    interrupt_keyboard = 1'b0;
    interrupt_disk = 1'b0;

    #23;
    reset = 1'b0;

    // ---- Phase A: keyboard alone ----
    wait (top_inst.PC_EX == 12);
    @(negedge clk); interrupt_keyboard = 1'b1; #10; interrupt_keyboard = 1'b0;

    // ---- Phase B: disk alone ----
    wait (top_inst.PC_EX == 20);
    @(negedge clk); interrupt_disk = 1'b1; #10; interrupt_disk = 1'b0;

    // ---- Phase C: simultaneous ----
    wait (top_inst.PC_EX == 28);
    @(negedge clk);
    interrupt_keyboard = 1'b1; interrupt_disk = 1'b1;
    #10;
    interrupt_keyboard = 1'b0; interrupt_disk = 1'b0;

    // ---- Phase D: keyboard outer, disk nests mid-ISR ----
    wait (top_inst.PC_EX == 36);
    @(negedge clk); interrupt_keyboard = 1'b1; #10; interrupt_keyboard = 1'b0;
    wait (top_inst.PC_EX == 160);
    @(negedge clk); interrupt_disk = 1'b1; #10; interrupt_disk = 1'b0;

    // ---- Phase E: disk outer, keyboard nests mid-ISR ----
    wait (top_inst.PC_EX == 44);
    @(negedge clk); interrupt_disk = 1'b1; #10; interrupt_disk = 1'b0;
    wait (top_inst.PC_EX == 240);
    @(negedge clk); interrupt_keyboard = 1'b1; #10; interrupt_keyboard = 1'b0;

    // ---- Phase F: keyboard self-nesting, 2-level ----
    wait (top_inst.PC_EX == 52);
    @(negedge clk); interrupt_keyboard = 1'b1; #10; interrupt_keyboard = 1'b0;
    wait (top_inst.PC_EX == 160);
    @(negedge clk); interrupt_keyboard = 1'b1; #10; interrupt_keyboard = 1'b0;

    // ---- Phase G: unsafe-window -- assert disk while KB ISR still has mie=0 ----
    wait (top_inst.PC_EX == 60);
    @(negedge clk); interrupt_keyboard = 1'b1; #10; interrupt_keyboard = 1'b0;
    wait (top_inst.PC_EX == 140); // inside KB ISR's save section, mie still 0 here
    @(negedge clk); interrupt_disk = 1'b1; #10; interrupt_disk = 1'b0;
    // no further action: disk's pending bit must be held and fire on its own
    // once KB's mie<=1 executes -- not injected "at" the reenable point this time.

    // ---- Phase H: keyboard self-nesting, 3-level ----
    wait (top_inst.PC_EX == 68);
    @(negedge clk); interrupt_keyboard = 1'b1; #10; interrupt_keyboard = 1'b0;
    wait (top_inst.PC_EX == 160);
    @(negedge clk); interrupt_keyboard = 1'b1; #10; interrupt_keyboard = 1'b0;
    wait (top_inst.PC_EX == 160);
    @(negedge clk); interrupt_keyboard = 1'b1; #10; interrupt_keyboard = 1'b0;

    #2000;
    $display("---FINAL---");
    $display("x2(sp)=%0d  x30(trap_count)=%0d  x6=%0d  x7=%0d  x28(end_marker)=%0d",
        top_inst.ID_stage_inst.register_file_inst.registers[2],
        top_inst.ID_stage_inst.register_file_inst.registers[30],
        top_inst.ID_stage_inst.register_file_inst.registers[6],
        top_inst.ID_stage_inst.register_file_inst.registers[7],
        top_inst.ID_stage_inst.register_file_inst.registers[28]);
    $finish;
end

always @(posedge clk) begin
    if (!reset)
        $display("t=%0t PC_EX=%0d mie=%b pend_kb=%b pend_dk=%b kb_taken=%b dk_taken=%b mepc=%0d mcause=%0d sp=%0d x6=%0d x7=%0d x30=%0d",
            $time, top_inst.PC_EX, top_inst.mie_val,
            top_inst.pending_keyboard, top_inst.pending_disk,
            top_inst.interrupt_keyboard_taken, top_inst.interrupt_disk_taken,
            top_inst.mepc_val, top_inst.mcause_val,
            top_inst.ID_stage_inst.register_file_inst.registers[2],
            top_inst.ID_stage_inst.register_file_inst.registers[6],
            top_inst.ID_stage_inst.register_file_inst.registers[7],
            top_inst.ID_stage_inst.register_file_inst.registers[30]);
end

initial begin
    $dumpfile("waves.vcd");
    $dumpvars();
end

endmodule