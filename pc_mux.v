module pc_mux(
    output reg [31:0] PC_Next,
    input [31:0] PC_Target_Predicted,
    input [31:0] PC_Plus_4,
    input [31:0] EX_RedirectPC,
    input EX_Override,
    input Predicted_Taken
);
always @(*) begin
    if (EX_Override)
        PC_Next = EX_RedirectPC;
    else if (Predicted_Taken)
        PC_Next = PC_Target_Predicted;
    else
        PC_Next = PC_Plus_4;
end
endmodule