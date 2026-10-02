module mpie
(
    input clk, reset, interrupt_taken, exception_taken, mret_taken, mpie_write_en, mie_out, csr_wdata_b0, mie_write_en,
    output reg mpie_out
    );

    always@(posedge clk or posedge reset)
    begin
        
        if(reset)
        begin
            mpie_out <= 1'b1;
        end

        else if(interrupt_taken | exception_taken)
        begin
            mpie_out <= (exception_taken & mie_write_en) ? csr_wdata_b0 : mie_out;
        end

        else if(mpie_write_en)
        begin
            mpie_out <= csr_wdata_b0;
        end

        else if(mret_taken)
        begin
            mpie_out <= 1'b1;
        end

        else
        begin
            mpie_out <= mpie_out;
        end
    end

endmodule