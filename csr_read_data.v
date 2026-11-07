module csr_read_data
(
    input mepc_sel, mie_sel, mcause_sel, mie_val, current_priority_sel, previous_priority_sel, mpie_sel, mpie_val, mtval_sel, mtvec_sel, mie_csr_sel, mip_sel, mscratch_sel, misa_sel,
    input mcycle_sel, mcycleh_sel, minstret_sel, minstreth_sel, cycle_sel, cycleh_sel, instret_sel, instreth_sel,
    input [31:0] mcycle_lo, mcycle_hi, minstret_lo, minstret_hi,
    input pending_keyboard, pending_disk,
    input [31:0] mepc_val, mcause_val, mtval_val, mtvec_val, mie_csr_val, mscratch_val, misa_val,
    input [1:0] current_priority, previous_priority,
    output reg [31:0] csr_read_val
);

always@(*)
begin
    csr_read_val = 32'b0;
    if(mepc_sel) csr_read_val = mepc_val;
    if(mie_sel) csr_read_val = {19'b0, 2'b11, 3'b0, mpie_val, 3'b0, mie_val, 3'b0};
    if(mcause_sel) csr_read_val = mcause_val;
    if(current_priority_sel) csr_read_val = {30'b0, current_priority};
    if(previous_priority_sel) csr_read_val = {30'b0, previous_priority};
    if(mtval_sel) csr_read_val = mtval_val;
    if(mtvec_sel) csr_read_val = mtvec_val;
    if(mie_csr_sel) csr_read_val = mie_csr_val;
    if(mip_sel) csr_read_val = {20'b0, (pending_keyboard | pending_disk), 11'b0};
    if(mscratch_sel) csr_read_val = mscratch_val;
    if(misa_sel) csr_read_val = misa_val;
    if(mcycle_sel | cycle_sel) csr_read_val = mcycle_lo;
    if(mcycleh_sel | cycleh_sel) csr_read_val = mcycle_hi;
    if(minstret_sel | instret_sel) csr_read_val = minstret_lo;
    if(minstreth_sel | instreth_sel) csr_read_val = minstret_hi;
end

endmodule