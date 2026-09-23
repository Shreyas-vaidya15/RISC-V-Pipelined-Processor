module tb();

reg clk, reset, interrupt;

top top_inst (
    .clk(clk),
    .reset(reset),
    .interrupt(interrupt)
);

always #5 clk = ~clk;

initial begin
    reset = 1'b1;
    clk = 1'b0;
    interrupt = 1'b0;

    #23;
    reset = 1'b0;

    // ---- Phase 1: addi x3 (addr 8) in EX -> mepc should = 8 ----
    #39;
    interrupt = 1'b1;
    #10;
    interrupt = 1'b0;

    // ---- Phase 2: redundant pulse mid-ISR (addr128 in EX) -> must be ignored (MIE=0) ----
    #100;
    interrupt = 1'b1;
    #10;
    interrupt = 1'b0;

    // ---- Phase 3: beq (addr 28) in EX -> mepc should = 28 ----
    #70;
    interrupt = 1'b1;
    #10;
    interrupt = 1'b0;

    // ---- Phase 4: lw (addr 44) in EX, load-use stall active ----
wait (top_inst.PC_EX == 44);
@(negedge clk);
interrupt = 1'b1;
#10;
interrupt = 1'b0;

// ---- Phase 5: jal (addr 56) in EX ----
wait (top_inst.PC_EX == 56);
@(negedge clk);
interrupt = 1'b1;
#10;
interrupt = 1'b0;

    #3000;
    $finish;
end

initial begin
    $dumpfile("waves.vcd");
    $dumpvars();
end

endmodule