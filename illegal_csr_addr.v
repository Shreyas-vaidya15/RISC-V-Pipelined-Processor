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
        
        if(csr_addr > 12'd5)
        begin
            illegal_csr_address = 1'b1;
        end

    end
end
endmodule