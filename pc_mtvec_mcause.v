module pc_mtvec_mcause
(
    input [31:0] mtvec_out,
    input interrupt_taken,
    input [1:0] interrupt_ID,
    output [31:0] pc_mtvec_mcause
);

reg [31:0] interrupt_offset;

always@(*)
begin
    case(interrupt_ID)
    2'd1, 2'd2 : interrupt_offset = 32'd44;
    default    : interrupt_offset = 32'd0;
    endcase
end

wire [31:0] mtvec_cleared = {mtvec_out[31:2], 2'b00};
assign pc_mtvec_mcause = (interrupt_taken & mtvec_out[0]) ? mtvec_cleared + interrupt_offset : mtvec_cleared;

endmodule