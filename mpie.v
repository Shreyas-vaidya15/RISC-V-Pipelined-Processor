module mpie
(
    input clk, reset, interrupt_taken, exception_taken, mret_taken, mpie_write_en, mie_out, mie_write_en,
    input mie_wdata,    // the value mie is being written with in this cycle (used when a trap happens in the same cycle)
    input mpie_wdata,   // the value software is writing into mpie itself
    output reg mpie_out
    );

    always@(posedge clk or posedge reset)
    begin
        
        if(reset)
        begin
            mpie_out <= 1'b0;
        end

        else if(interrupt_taken | exception_taken)
        begin
            mpie_out <= (exception_taken & mie_write_en) ? mie_wdata : mie_out;
        end

        else if(mpie_write_en)
        begin
            mpie_out <= mpie_wdata;
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