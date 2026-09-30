module tb_exc();

reg clk = 0, reset = 1;

top top_inst (
    .clk(clk),
    .reset(reset),
    .interrupt_keyboard(1'b0),
    .interrupt_disk(1'b0)
);

always #5 clk = ~clk;

`define REG(n) top_inst.ID_stage_inst.register_file_inst.registers[n]

integer errors = 0;
integer exc_count = 0;

task check;
    input [8*20-1:0] what;
    input integer got;
    input integer exp;
begin
    if (got !== exp) begin
        errors = errors + 1;
        $display("  [FAIL] %0s: got %0d, expected %0d", what, got, exp);
    end
    else
        $display("  [ ok ] %0s = %0d", what, got);
end
endtask

// Count exceptions and report what was recorded at the moment of each one
always @(negedge clk) begin
    if (!reset && top_inst.exception_taken) begin
        exc_count = exc_count + 1;
        $display(">>> EXCEPTION #%0d  PC_ID=%0d  vector=%0d  t=%0t",
                 exc_count, top_inst.PC_ID, top_inst.pc_mtvec_mcause_val, $time);
    end
    if (!reset && top_inst.interrupt_taken) begin
        errors = errors + 1;
        $display(">>> [FAIL] unexpected interrupt taken at t=%0t", $time);
    end
end

// Watchdog in case something hangs
initial begin
    #5000;
    $display("---WATCHDOG FIRED---");
    $finish;
end

initial begin
    #23 reset = 0;
    #500;

    $display("---FINAL---");
    check("x5  (sum, expect 50)", `REG(5),  50);
    check("x28 (end marker)",     `REG(28), 99);
    check("x30 (exc count)",      `REG(30), 1);
    check("x31 (mcause)",         `REG(31), 2);
    check("x29 (return PC)",      `REG(29), 20);
    check("mepc",                 top_inst.mepc_val, 20);
    check("exceptions seen",      exc_count, 1);

    if (errors == 0) $display("=== EXCEPTION TEST PASSED ===");
    else             $display("=== %0d CHECK(S) FAILED ===", errors);
    $finish;
end

initial begin
    $dumpfile("waves.vcd");
    $dumpvars();
end

endmodule