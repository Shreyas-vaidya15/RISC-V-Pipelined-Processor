// Instruction memory for running compiled C programs (c_run build).
// Same module name and ports as the sweep version, so IF_stage is unchanged.
// Byte shelf, little-endian read, filled from a hex file made by objcopy -O verilog.
// Default file: prog.hex. Pick another at run time with:  vvp sim_c +hex=other.hex
// The file name is relative to the folder you run vvp from.

module inst_memory #(parameter DEPTH = 256) (input [31:0] addr, output [31:0] data);

reg [7:0] mem [0:DEPTH*4-1];

integer i;
reg [8*256-1:0] hexfile;      // file name, up to 256 characters

initial begin
    // everything not covered by the hex file reads as 0, never X
    for (i = 0; i < DEPTH*4; i = i + 1)
        mem[i] = 8'h00;

    if (!$value$plusargs("hex=%s", hexfile))
        hexfile = "prog.hex";

    $readmemh(hexfile, mem);
end

assign data = {mem[addr+3], mem[addr+2], mem[addr+1], mem[addr]};

endmodule