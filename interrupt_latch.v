module interrupt_latch
(
    input clk,reset,
    input interrupt_in, interrupt_taken,
    output reg interrupt_pending
);

always@(posedge clk or posedge reset)
begin

    if(reset)
    begin
        interrupt_pending <= 1'b0;
    end

    else if(interrupt_taken)
    begin
        interrupt_pending <= 1'b0;
    end

    else if(interrupt_in)
    begin
        interrupt_pending <= 1'b1;
    end

    else
    begin
        interrupt_pending <= interrupt_pending;
    end

end
endmodule