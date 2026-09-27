module csr_read_data
(
    input mepc_write_en, mie_write_en, mcause_write_en, mie_val,
    input [31:0] mepc_val, mcause_val,
    output reg [31:0] csr_read_val
);

always@(*)
begin
    csr_read_val = 32'b0;
    if(mepc_write_en) csr_read_val = mepc_val;
    if(mie_write_en) csr_read_val = {31'b0, mie_val};
    if(mcause_write_en) csr_read_val = mcause_val;
end

endmodule