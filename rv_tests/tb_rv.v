`timescale 1ns/1ps
// rv32ui test runner: +hex=<text hex> +data=<data hex> [+wait=N]
module tb_rv();
localparam LIMIT = 20000;
reg clk, reset;
reg [3:0] wait_cycles;
integer cyc, excs, w;
reg [8*256-1:0] datafile;

soc_top soc_inst (.clk(clk), .reset(reset), .interrupt_keyboard(1'b0), .interrupt_disk(1'b0), .WAIT_CYCLES(wait_cycles));
defparam soc_inst.cpu_inst.IF_stage_inst.DEPTH = 1024;

`define RV_CPU soc_inst.cpu_inst
`define RV_REG(n) soc_inst.cpu_inst.ID_stage_inst.register_file_inst.registers[n]
`define RV_DMEM soc_inst.data_slave_inst.data_memory_inst.mem

initial clk = 1'b0;
always #5 clk = ~clk;

always @(negedge clk) if (!reset && `RV_CPU.exception_taken) excs = excs + 1;

initial begin
    reset = 1'b1; wait_cycles = 4'd0; cyc = 0; excs = 0;
    if ($value$plusargs("wait=%d", w)) wait_cycles = w;
    #1;
    if ($value$plusargs("data=%s", datafile)) $readmemh(datafile, `RV_DMEM);
    #21;
    reset = 1'b0;
    while (`RV_REG(30) !== 32'd99 && cyc < LIMIT) begin
        @(negedge clk);
        cyc = cyc + 1;
    end
    if (cyc >= LIMIT)
        $display("RV RESULT: TIMEOUT after %0d cycles (PC_IF=%0d x3=%0d)", cyc, `RV_CPU.PC_IF, `RV_REG(3));
    else if (`RV_REG(10) === 32'd0 && excs == 0)
        $display("RV RESULT: PASS (%0d cycles)", cyc);
    else
        $display("RV RESULT: FAIL x10=%0d (check #%0d) x3=%0d exceptions=%0d mepc=0x%0h mcause=0x%0h", `RV_REG(10), `RV_REG(10) >> 1, `RV_REG(3), excs, `RV_CPU.mepc_val, `RV_CPU.mcause_val);
    $finish;
end
endmodule
