module EX_stage
(
    input ALUSrc, Branch, Jump, Predicted_Taken, IsCSR,
    input [3:0] ALUControl,
    input [31:0] ImmExt, RD1, RD2, PC, Instr, PC_Plus_4, csr_read_val,
    output IsJalr, EX_Override, Actual_Taken,
    output [31:0] Result, PCTarget,
    output reg [31:0] EX_RedirectPC
);

wire Zero ,Overflow, Carry, Negative, Mispredict;
wire [31:0] B;

reg [31:0] A;
wire IsAuipc = (Instr[6:0] == 7'b0010111);
wire BranchDecision = Instr[14] ? Result[0] : Zero;
assign Actual_Taken = BranchDecision ^ Instr[12];
assign Mispredict = (Branch & (Actual_Taken ^ Predicted_Taken));
assign EX_Override = Jump | Mispredict;
assign IsJalr = (Instr[6:0] == 7'b1100111);

always@(*)
begin

    if(IsCSR && (Instr[14:12] == 3'b110 || Instr[14:12] == 3'b111))
    begin
        A = ImmExt;
    end

    else if(IsAuipc)
    begin
        A = PC;
    end

    else
    begin
        A = RD1;
    end
end

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
    .csr_read_val(csr_read_val),
    .ALUSrc(ALUSrc),
    .IsCSR(IsCSR),
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