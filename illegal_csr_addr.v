module illegal_csr_addr
(
    input [11:0] csr_addr,
    input [2:0] funct3,
    input [4:0] rs1,
    input IsCSR,
    output reg illegal_csr_address
);

// A CSR instruction writes the CSR unless it is csrrs/csrrc/csrrsi/csrrci (funct3[1] = 1) with rs1/uimm = 0.
// Same rule as csr_write_EX in top.v.
wire csr_writes = ~(funct3[1] & (rs1 == 5'd0));

// CSR address bits [11:10] = 2'b11 means the CSR is read-only (mvendorid, mhartid, cycle, instret, ...).
wire csr_read_only = (csr_addr[11:10] == 2'b11);

always@(*)
begin

    illegal_csr_address = 1'b0;

    if(IsCSR)
    begin

        case(csr_addr)
            12'h300, 12'h301, 12'h304, 12'h305, 12'h340, 12'h341, 12'h342, 12'h343, 12'h344, 12'h7C0, 12'h7C1, 12'hB00, 12'hB02, 12'hB80, 12'hB82, 12'hC00, 12'hC02, 12'hC80, 12'hC82, 12'hF11, 12'hF12, 12'hF13, 12'hF14: illegal_csr_address = 1'b0;
            default: illegal_csr_address = 1'b1;
        endcase

        // Writing a read-only CSR is illegal even though the address itself is implemented.
        if(csr_read_only & csr_writes)
            illegal_csr_address = 1'b1;

    end
end
endmodule