module pc_mtvec_mcause
(
    input [31:0]mtvec_out, mcause,
    output [31:0] pc_mtvec_mcause
);

wire [31:0] mid_mcause = {1'b0, mcause[30:0]} << 2;
wire [31:0] mtvec_cleared = {mtvec_out[31:2], 2'b00};
assign pc_mtvec_mcause = (mcause[31] & mtvec_out[0]) ? mtvec_cleared + mid_mcause : mtvec_cleared;

endmodule