module load_store_access_fault #(parameter DEPTH = 64)
(
    input IsLoad,
    input MemWrite,
    input [31:0] ALUResult,
    output load_store_access_fault
);

assign load_store_access_fault = (IsLoad | MemWrite) ? (ALUResult >= (DEPTH * 4)) : 1'b0;

endmodule