module instruction_address_misalign
(
    input Actual_Taken, 
    input Branch,
    input Jump, 
    input IsJalr,
    input ALUResult_b1, 
    input PCTarget_b1,
    output reg instruction_address_misalign
);

always@(*)
begin

    instruction_address_misalign = 1'b0;

    if((Branch & Actual_Taken) | (Jump & ~IsJalr))
    begin

        if(PCTarget_b1)
        begin
            instruction_address_misalign = 1'b1;
        end

    end

    if(IsJalr)
    begin
        
        if(ALUResult_b1)
        begin
            instruction_address_misalign = 1'b1;
        end

    end

end
endmodule