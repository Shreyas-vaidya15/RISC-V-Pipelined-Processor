module mie_csr
(
    input clk, 
    input reset,
    input mie_csr_write_en,
    input [31:0] csr_wdata,
    output reg [31:0] mie_csr_out
);

always@(posedge clk or posedge reset)
begin
    
    if(reset)
    begin
        mie_csr_out <= 32'b0;
    end

    else if(mie_csr_write_en)
    begin
        mie_csr_out <= {20'd0, {csr_wdata[11]}, 3'd0, {csr_wdata[7]}, 7'd0};
    end

    else
    begin
        mie_csr_out <= mie_csr_out;
    end

end
endmodule