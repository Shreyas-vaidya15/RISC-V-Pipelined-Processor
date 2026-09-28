module pc_mux(
    output reg [31:0] PC_Next,
    input [31:0] PC_Target_Predicted,
    input [31:0] PC_Plus_4,
    input [31:0] EX_RedirectPC,
    input [31:0] mepc,
    input [31:0] pc_mtvec_mcause,
    input EX_Override,
    input Mret_taken,
    input interrupt_taken,
    input Predicted_Taken
);
always @(*) 
begin
    if (interrupt_taken)
    begin
        PC_Next = pc_mtvec_mcause;
    end

    else if (EX_Override)
    begin
        PC_Next = EX_RedirectPC;
    end
    
    else if(Mret_taken)
    begin
        PC_Next = mepc;
    end

    else if (Predicted_Taken)
    begin
        PC_Next = PC_Target_Predicted;
    end

    else
    begin
        PC_Next = PC_Plus_4;
    end

end
endmodule