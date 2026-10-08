module mscratch
(
    input clk,
    input reset,
    input mscratch_write_en,
    input [31:0] csr_wdata,
    output reg [31:0] mscratch_out
);

always@(posedge clk or posedge reset)
begin
    
    if(reset)
    begin
        mscratch_out <= 32'b0;
    end

    else if(mscratch_write_en)
    mscratch_out <= csr_wdata;

    else
    begin
        mscratch_out <= mscratch_out;
    end
    
end
endmodule