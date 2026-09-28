module csr_addr_decoder
(
    input [11:0] csr_addr,
    input IsCSR,
    output reg mepc_write_en, mie_write_en, mcause_write_en, current_priority_write_en, previous_priority_write_en
);

always@(*)
begin
    mepc_write_en = 1'b0;
    mie_write_en = 1'b0;
    mcause_write_en = 1'b0;
    current_priority_write_en = 1'b0;
    previous_priority_write_en = 1'b0;

if(IsCSR && (csr_addr == 12'd0)) mepc_write_en = 1'b1;
if(IsCSR && (csr_addr == 12'd1)) mie_write_en = 1'b1;
if(IsCSR && (csr_addr == 12'd2)) mcause_write_en = 1'b1;
if(IsCSR && (csr_addr == 12'd3)) current_priority_write_en = 1'b1;
if(IsCSR && (csr_addr == 12'd4)) previous_priority_write_en = 1'b1;

end
endmodule