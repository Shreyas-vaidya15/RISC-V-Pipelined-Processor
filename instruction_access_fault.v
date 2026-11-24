// Fetch address outside the instruction memory window [BASE, BASE + DEPTH*4).
// (PC_IF - BASE) wraps for PC_IF < BASE, so one unsigned compare covers both ends.
module instruction_access_fault #(parameter DEPTH = 256, parameter [31:0] BASE = 32'h0)
(
    input [31:0] PC_IF,
    output instruction_access_fault
);

assign instruction_access_fault = ((PC_IF - BASE) >= DEPTH * 4);

endmodule