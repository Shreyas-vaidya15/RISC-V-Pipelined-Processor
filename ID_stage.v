module ID_stage
(
    input clk, we, 
    input [4:0] wa,
    input [31:0] wd, Instr_In,
    output Jump, Branch, MemWrite, RegWrite, ALUSrc, Mret_taken, IsCSR, Illegal_opcode, illegal_funct3_csr, illegal_csr_address, IsLoad, Illegal_System_Imm, Ecall, Ebreak,
    output [1:0] ResultSrc,
    output [3:0] ALUControl,
    output [31:0] rd1, rd2, ImmExt
);

wire [2:0] ALUop;
wire [2:0] ImmSrc;

main_decoder main_decoder_inst
(
    .RegWrite(RegWrite),
    .ImmSrc(ImmSrc),
    .ALUSrc(ALUSrc),
    .MemWrite(MemWrite),
    .ResultSrc(ResultSrc),
    .Branch(Branch),
    .ALUop(ALUop),
    .Jump(Jump),
    .Mret_taken(Mret_taken),
    .IsCSR(IsCSR),
    .Illegal_opcode(Illegal_opcode),
    .illegal_funct3(illegal_funct3_csr),
    .IsLoad(IsLoad),
    .Illegal_System_Imm(Illegal_System_Imm),
    .Ecall(Ecall),
    .Ebreak(Ebreak),
    .System_Imm(Instr_In[31:20]),
    .op(Instr_In[6:0]),
    .funct3(Instr_In[14:12])
);

alu_decoder alu_decoder_inst
(
    .ALUOp(ALUop),
    .funct3(Instr_In[14:12]),
    .funct7b5(Instr_In[30]),
    .opb5(Instr_In[5]),
    .ALUControl(ALUControl)
);

register_file register_file_inst
(
    .rd1(rd1),
    .rd2(rd2),
    .clk(clk),
    .rs1(Instr_In[19:15]),
    .rs2(Instr_In[24:20]),
    .we(we),
    .wd(wd),
    .wa(wa)
);

sign_extender sign_extender_inst
(
    .ImmExt(ImmExt),
    .Instr(Instr_In),
    .ImmSrc(ImmSrc)
);

illegal_csr_addr illegal_csr_addr_inst
(
    .csr_addr(Instr_In[31:20]),
    .IsCSR(IsCSR),
    .illegal_csr_address(illegal_csr_address)
);
endmodule