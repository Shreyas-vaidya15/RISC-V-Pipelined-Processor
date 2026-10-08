module illegal_csr_addr
(
    input [11:0] csr_addr,
    input IsCSR,
    output reg illegal_csr_address
);

always@(*)
begin

    illegal_csr_address = 1'b0;

    if(IsCSR)
    begin
        
        case(csr_addr)
            12'h300, 12'h301, 12'h304, 12'h305, 12'h340, 12'h341, 12'h342, 12'h343, 12'h344, 12'h7C0, 12'h7C1: illegal_csr_address = 1'b0;
            default: illegal_csr_address = 1'b1;
        endcase

    end
end
endmodule