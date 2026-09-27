module alu_decoder(
	input [2:0] ALUOp,
	input [2:0] funct3,
	input funct7b5,
	input opb5,
	output reg [3:0] ALUControl);

always @(*) begin
	case (ALUOp)
		3'b000: ALUControl = 4'b0000;
		3'b001: begin
    case (funct3)
        3'b000: ALUControl = 4'b0001;
        3'b001: ALUControl = 4'b0001; 
        3'b100: ALUControl = 4'b0101;
        3'b101: ALUControl = 4'b0101; 
        3'b110: ALUControl = 4'b0110; 
        3'b111: ALUControl = 4'b0110; 
        default: ALUControl = 4'bxxxx;
    endcase
end
		
		3'b010: begin
		       case (funct3)
				3'b000: ALUControl = (funct7b5 & opb5) ? 4'b0001 : 4'b0000;
				3'b001: ALUControl = 4'b1010;
				3'b010: ALUControl = 4'b0101;
				3'b011: ALUControl = 4'b0110;
				3'b100: ALUControl = 4'b0100;
				3'b101: ALUControl = funct7b5 ? 4'b1011: 4'b1100;
				3'b110: ALUControl = 4'b0011;
				3'b111: ALUControl = 4'b0010;
				default : ALUControl = 4'bxxxx;
			endcase
		end
		
		3'b011: ALUControl = opb5 ? 4'b1001 : 4'b1000;
		
		3'b100: begin
			case(funct3)
			3'b000, 3'b001, 3'b101 : ALUControl = 4'bxxxx;
			3'b010, 3'b110 : ALUControl = 4'b0011;
			3'b011, 3'b111 : ALUControl = 4'b1101;
			endcase
		end
		default : ALUControl = 4'bxxxx;
	endcase
end

endmodule
