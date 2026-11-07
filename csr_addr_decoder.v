module csr_addr_decoder
(
    input [11:0] csr_addr,
    input IsCSR,
    output reg mepc_sel, mie_sel, mcause_sel, current_priority_sel, previous_priority_sel, mpie_sel, mtval_sel, mtvec_sel, mie_csr_sel, mip_sel, mscratch_sel, misa_sel,
    output reg mcycle_sel, mcycleh_sel, minstret_sel, minstreth_sel, cycle_sel, cycleh_sel, instret_sel, instreth_sel
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
    mcycle_sel = 1'b0;
    mcycleh_sel = 1'b0;
    minstret_sel = 1'b0;
    minstreth_sel = 1'b0;
    cycle_sel = 1'b0;
    cycleh_sel = 1'b0;
    instret_sel = 1'b0;
    instreth_sel = 1'b0;
    
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

// Counters. The m-versions (read/write) and the read-only user copies get separate selects, so a write enable
// is only ever built from the m-versions.
if(IsCSR && (csr_addr == 12'hB00)) mcycle_sel = 1'b1;
if(IsCSR && (csr_addr == 12'hB80)) mcycleh_sel = 1'b1;
if(IsCSR && (csr_addr == 12'hB02)) minstret_sel = 1'b1;
if(IsCSR && (csr_addr == 12'hB82)) minstreth_sel = 1'b1;
if(IsCSR && (csr_addr == 12'hC00)) cycle_sel = 1'b1;
if(IsCSR && (csr_addr == 12'hC80)) cycleh_sel = 1'b1;
if(IsCSR && (csr_addr == 12'hC02)) instret_sel = 1'b1;
if(IsCSR && (csr_addr == 12'hC82)) instreth_sel = 1'b1;


end
endmodule