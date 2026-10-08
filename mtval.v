module mtval
(
    input clk, reset, interrupt_taken, exception_taken, mtval_write_en,
    input [31:0] mtval_in, csr_wdata,
    output reg[31:0] mtval_out
);

always@(posedge clk or posedge reset)
begin
    
    if(reset)
    begin
        mtval_out <= 32'd0;
    end

    else if(interrupt_taken)
    begin
        mtval_out <= 32'b0;
    end

    else if(exception_taken)
    begin
        mtval_out <= mtval_in;
    end

    else if(mtval_write_en)
    begin
        mtval_out <= csr_wdata;
    end

    else
    begin
        mtval_out <= mtval_out;
    end

end

endmodule