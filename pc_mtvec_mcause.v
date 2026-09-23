module pc_mtvec_mcause
(
    input [31:0]mtvec, mcause,
    output [31:0] pc_mtvec_mcause
);

wire [31:0] mid_mcause = {1'b0, mcause[30:0]} << 2;
assign pc_mtvec_mcause = mtvec + mid_mcause;

endmodule