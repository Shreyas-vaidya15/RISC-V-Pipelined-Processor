module misaligned_detect
(
    input IsLoad, MemWrite,
    input [2:0] funct3,
    input [31:0] addr,
    output misaligned,
    output misaligned_store
);

wire misaligned_word = funct3[1] & (addr[1] | addr[0]);
wire misaligned_half_word = funct3[0] & addr[0];

assign misaligned = (IsLoad | MemWrite) &(misaligned_word | misaligned_half_word);
assign misaligned_store = MemWrite;

endmodule