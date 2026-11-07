module stall_unit
(
    input [6:0] ID_EX_opcode,
    input [6:0] IF_ID_opcode,
    input [2:0] IF_ID_funct3,
    input [4:0] IF_ID_rs1, IF_ID_rs2, ID_EX_WA,
    output reg Stall
);

wire uses_rs1 = (IF_ID_opcode == 7'b1100111) | (IF_ID_opcode == 7'b1100011) | (IF_ID_opcode == 7'b0000011) |
                (IF_ID_opcode == 7'b0100011) | (IF_ID_opcode == 7'b0010011) | (IF_ID_opcode == 7'b0110011) |
                ((IF_ID_opcode == 7'b1110011) & (IF_ID_funct3 != 3'b000) & ~IF_ID_funct3[2]);   // csrrw/csrrs/csrrc (not the immediate forms)

wire uses_rs2 = (IF_ID_opcode == 7'b1100011) | (IF_ID_opcode == 7'b0100011) | (IF_ID_opcode == 7'b0110011);

always@(*)
begin

if(ID_EX_opcode == 7'b0000011 && ID_EX_WA != 5'b0 &&
   ((uses_rs1 && ID_EX_WA == IF_ID_rs1) || (uses_rs2 && ID_EX_WA == IF_ID_rs2)))
   begin
    Stall = 1'b1;
   end

else
   begin
    Stall = 1'b0;
   end
end

endmodule