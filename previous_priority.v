module previous_priority
(
    input [1:0] current_priority, csr_wdata,
    input clk, reset, interrupt_taken, previous_priority_write_en, exception_taken, current_priority_write_en,
    output reg [1:0] previous_priority
);

always@(posedge clk or posedge reset)
begin

    if(reset)
    begin
        previous_priority <= 2'b00;
    end

    else if(interrupt_taken)
    begin
        previous_priority <= current_priority;
    end

    else if(exception_taken)
    begin
        previous_priority <= current_priority_write_en ? csr_wdata : current_priority;
    end

    else if(previous_priority_write_en)
    begin
        previous_priority <= csr_wdata;
    end

    else
    begin
        previous_priority <= previous_priority;
    end
end
endmodule