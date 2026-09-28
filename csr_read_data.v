module csr_read_data
(
    input mepc_write_en, mie_write_en, mcause_write_en, mie_val, current_priority_write_en, previous_priority_write_en,
    input [31:0] mepc_val, mcause_val,
    input [1:0] current_priority, previous_priority,
    output reg [31:0] csr_read_val
);

always@(*)
begin
    csr_read_val = 32'b0;
    if(mepc_write_en) csr_read_val = mepc_val;
    if(mie_write_en) csr_read_val = {31'b0, mie_val};
    if(mcause_write_en) csr_read_val = mcause_val;
    if(current_priority_write_en) csr_read_val = {30'b0, current_priority};
    if(previous_priority_write_en) csr_read_val = {30'b0, previous_priority};
end

endmodule