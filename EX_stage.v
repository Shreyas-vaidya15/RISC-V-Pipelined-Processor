module EX_stage
(
    input ALUSrc, Branch, Jump, Predicted_Taken,
    input [3:0] ALUControl,
    input [31:0] ImmExt, RD1, RD2, PC, Instr, PC_Plus_4,
    output IsJalr, EX_Override,
    output [31:0] Result, PCTarget,
    output reg [31:0] EX_RedirectPC
);

wire Zero ,Overflow, Carry, Negative, Mispredict, Actual_Taken;
wire [31:0] B;

wire IsAuipc = (Instr[6:0] == 7'b0010111);
wire [31:0] A = IsAuipc ? PC : RD1;
wire BranchDecision = Instr[14] ? Result[0] : Zero;
assign Actual_Taken = BranchDecision ^ Instr[12];
assign Mispredict = (Branch & (Actual_Taken ^ Predicted_Taken));
assign EX_Override = Jump | Mispredict;
assign IsJalr = (Instr[6:0] == 7'b1100111);

always@(*)
begin

if (IsJalr)
EX_RedirectPC = {Result[31:1], 1'b0};

else if (Jump)
EX_RedirectPC = PCTarget;

else if (Mispredict)
begin

    if(Actual_Taken)
        EX_RedirectPC = PCTarget;

    else
        EX_RedirectPC = PC_Plus_4;
end

else

    EX_RedirectPC = PC_Plus_4;
end

alu_mux alu_mux_inst
(
    .RD2(RD2),
    .ImmExt(ImmExt),
    .ALUSrc(ALUSrc),
    .B(B)
);

alu alu_inst
(
    .A(A),
    .B(B),
    .ALUControl(ALUControl),
    .Result(Result),
    .Zero(Zero),
    .Overflow(Overflow),
    .Carry(Carry),
    .Negative(Negative)
);

pc_target pc_target_inst
(
    .PC(PC),
    .ImmExt(ImmExt),
    .PCTarget(PCTarget)
);

endmodule