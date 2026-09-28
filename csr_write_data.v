module csr_write_data
(
    input [31:0] ALUResult, ImmExt, rs1,
    input [2:0] funct3,
    output reg [31:0] csr_wdata
);

always@(*)
begin
    case(funct3)
    3'b001 : csr_wdata = rs1;
    3'b010, 3'b011, 3'b110, 3'b111 : csr_wdata = ALUResult;
    3'b101 : csr_wdata = ImmExt;
    default : csr_wdata = 32'b0;
    endcase
end
endmodule