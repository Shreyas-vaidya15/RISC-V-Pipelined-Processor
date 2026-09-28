module interrupt_priority_encoder
(
    input pending_keyboard, pending_disk,
    output reg [1:0] interrupt_ID
);

always@(*)
begin

    if(pending_disk)
    begin
        interrupt_ID = 2'd2;
    end

    else if(pending_keyboard)
    begin
        interrupt_ID = 2'd1;
    end

    else
    begin
        interrupt_ID = 2'd0;
    end

end
endmodule