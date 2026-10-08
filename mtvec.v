module mtvec
(
    input clk, reset, mtvec_write_en,
    input [31:0] csr_wdata,
    output reg [31:0] mtvec_out
);

always@(posedge clk or posedge reset)
begin
    
    if(reset)
    begin
        mtvec_out <= 32'd101;
    end

    else if(mtvec_write_en)
    begin
        mtvec_out <= {csr_wdata[31:2], 1'b0, csr_wdata[0]};
    end

    else
    begin
        mtvec_out <= mtvec_out;
    end

end

endmodule