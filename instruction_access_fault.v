module instruction_access_fault #(parameter DEPTH = 256)
(
    input [31:0] PC_IF,
    output instruction_access_fault
);

assign instruction_access_fault = (PC_IF >= DEPTH * 4);

endmodule