module csr_addr_decoder
(
    input [11:0] csr_addr,
    input IsCSR,
    output reg mepc_sel, mie_sel, mcause_sel, current_priority_sel, previous_priority_sel, mpie_sel, mtval_sel, mtvec_sel, mie_csr_sel, mip_sel, mscratch_sel, misa_sel
);

always@(*)
begin
    mepc_sel = 1'b0;
    mie_sel = 1'b0;
    mcause_sel = 1'b0;
    current_priority_sel = 1'b0;
    previous_priority_sel = 1'b0;
    mpie_sel = 1'b0;
    mtval_sel = 1'b0;
    mtvec_sel = 1'b0;
    mie_csr_sel = 1'b0;
    mip_sel = 1'b0;
    mscratch_sel = 1'b0;
    misa_sel = 1'b0;
    
if(IsCSR && (csr_addr == 12'h300)) 
begin 
    mie_sel = 1'b1; 
    mpie_sel = 1'b1; 
end

if(IsCSR && (csr_addr == 12'h301)) misa_sel = 1'b1;
if(IsCSR && (csr_addr == 12'h304)) mie_csr_sel = 1'b1;
if(IsCSR && (csr_addr == 12'h305)) mtvec_sel = 1'b1;
if(IsCSR && (csr_addr == 12'h340)) mscratch_sel = 1'b1;
if(IsCSR && (csr_addr == 12'h341)) mepc_sel = 1'b1;
if(IsCSR && (csr_addr == 12'h342)) mcause_sel = 1'b1;
if(IsCSR && (csr_addr == 12'h343)) mtval_sel = 1'b1;
if(IsCSR && (csr_addr == 12'h344)) mip_sel = 1'b1;
if(IsCSR && (csr_addr == 12'h7C0)) current_priority_sel = 1'b1;
if(IsCSR && (csr_addr == 12'h7C1)) previous_priority_sel = 1'b1;


end
endmodule