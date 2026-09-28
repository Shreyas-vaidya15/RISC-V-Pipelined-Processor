module current_priority
(
    input [1:0] interrupt_ID, csr_wdata, previous_priority,
    input interrupt_taken, clk, reset, current_priority_write_en, mret_taken,
    output reg [1:0] current_priority
);

always@(posedge clk or posedge reset)
begin

    if(reset)
    begin
        current_priority <= 2'b00;
    end

    else if(interrupt_taken)
    begin
        current_priority <= interrupt_ID;
    end

    else if(mret_taken)
    begin
        current_priority <= previous_priority;
    end
    
    else if(current_priority_write_en)
    begin
        current_priority <= csr_wdata;
    end

    else
    begin
        current_priority <= current_priority;
    end
end
endmodule