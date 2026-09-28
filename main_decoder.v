module main_decoder(
	output reg RegWrite,
	output reg [2:0] ImmSrc,
	output reg ALUSrc,
	output reg MemWrite,
	output reg [1:0] ResultSrc,
	output reg Branch,
	output reg [2:0] ALUop,
	output reg Jump,
	output reg Mret_taken,
	output reg IsCSR,
	input [6:0] op,
	input [2:0] funct3
);

always @(*) begin
	case (op)

		7'b0000000: begin
		       RegWrite = 1'b0;
       		       ImmSrc = 3'b000;
		       ALUSrc = 1'b0;
		       MemWrite = 1'b0;
		       ResultSrc = 2'b00;
		       Branch = 1'b0;
		       ALUop = 3'b000;
		       Jump = 1'b0;
			   Mret_taken = 1'b0;
			   IsCSR = 1'b0;
	       end

	       7'b0000011: begin
		       RegWrite = 1'b1;
       		       ImmSrc = 3'b000;
		       ALUSrc = 1'b1;
		       MemWrite = 1'b0;
		       ResultSrc = 2'b01;
		       Branch = 1'b0;
		       ALUop = 3'b000;
		       Jump = 1'b0;
			   Mret_taken = 1'b0;
			   IsCSR = 1'b0;
	       end

	       7'b0100011: begin
		       RegWrite = 1'b0;
       		       ImmSrc = 3'b001;
		       ALUSrc = 1'b1;
		       MemWrite = 1'b1;
		       ResultSrc = 2'b00;
		       Branch = 1'b0;
		       ALUop = 3'b000;
		       Jump = 1'b0;
			   Mret_taken = 1'b0;
			   IsCSR = 1'b0;
	       end

	       7'b0110011: begin
		       RegWrite = 1'b1;
       		       ImmSrc = 3'bxxx;
		       ALUSrc = 1'b0;
		       MemWrite = 1'b0;
		       ResultSrc = 2'b00;
		       Branch = 1'b0;
		       ALUop = 3'b010;
		       Jump = 1'b0;
			   Mret_taken = 1'b0;
			   IsCSR = 1'b0;
	       end

	       7'b0010011: begin
		       RegWrite = 1'b1;
       		       ImmSrc = 3'b000;
		       ALUSrc = 1'b1;
		       MemWrite = 1'b0;
		       ResultSrc = 2'b00;
		       Branch = 1'b0;
		       ALUop = 3'b010;
		       Jump = 1'b0;
			   Mret_taken = 1'b0;
			   IsCSR = 1'b0;
	       end

	       7'b1100011: begin
		       RegWrite = 1'b0;
       		       ImmSrc = 3'b010;
		       ALUSrc = 1'b0;
		       MemWrite = 1'b0;
		       ResultSrc = 2'b00;
		       Branch = 1'b1;
		       ALUop = 3'b001;
		       Jump = 1'b0;
			   Mret_taken = 1'b0;
			   IsCSR = 1'b0;
	       end

	       7'b1101111: begin
		       RegWrite = 1'b1;
       		       ImmSrc = 3'b011;
		       ALUSrc = 1'b0;
		       MemWrite = 1'b0;
		       ResultSrc = 2'b10;
		       Branch = 1'b0;
		       ALUop = 3'b000;
		       Jump = 1'b1;
			   Mret_taken = 1'b0;
			   IsCSR = 1'b0;
	       end

	       7'b1100111: begin
		       RegWrite = 1'b1;
       		       ImmSrc = 3'b000;
		       ALUSrc = 1'b1;
		       MemWrite = 1'b0;
		       ResultSrc = 2'b10;
		       Branch = 1'b0;
		       ALUop = 3'b000;
		       Jump = 1'b1;
			   Mret_taken = 1'b0;
			   IsCSR = 1'b0;
	       end

	       7'b0110111: begin
        	RegWrite = 1'b1;
        	ImmSrc = 3'b100;
        	ALUSrc = 1'b1;
        	MemWrite = 1'b0;
        	ResultSrc = 2'b00;
        	Branch = 1'b0;
        	ALUop = 3'b011;
        	Jump = 1'b0;
			Mret_taken = 1'b0;
			IsCSR = 1'b0;
			end

	       7'b0010111: begin
		       RegWrite = 1'b1;
       		       ImmSrc = 3'b100;
		       ALUSrc = 1'b1;
		       MemWrite = 1'b0;
		       ResultSrc = 2'b00;
		       Branch = 1'b0;
		       ALUop = 3'b011;
		       Jump = 1'b0;
			   Mret_taken = 1'b0;
			   IsCSR = 1'b0;
	       end

		   7'b1110011: begin
			
			case(funct3)
			3'b000 : 
			begin
			   RegWrite = 1'b0;
	   		   ImmSrc = 3'b000;
		       ALUSrc = 1'b0;
		       MemWrite = 1'b0;
		       ResultSrc = 2'b00;
		       Branch = 1'b0;
		       ALUop = 3'b000;
		       Jump = 1'b0;
			   Mret_taken = 1'b1;
			   IsCSR = 1'b0;
			end

			3'b001, 3'b010, 3'b011:
			begin
			   RegWrite = 1'b1;
	   		   ImmSrc = 3'bxxx;
		       ALUSrc = 1'b0;
		       MemWrite = 1'b0;
		       ResultSrc = 2'b11;
		       Branch = 1'b0;
		       ALUop = 3'b100;
		       Jump = 1'b0;
			   Mret_taken = 1'b0;
			   IsCSR = 1'b1;
			end 

			3'b101, 3'b110, 3'b111:
			begin
			   RegWrite = 1'b1;
	   		   ImmSrc = 3'b101;
		       ALUSrc = 1'b0;
		       MemWrite = 1'b0;
		       ResultSrc = 2'b11;
		       Branch = 1'b0;
		       ALUop = 3'b100;
		       Jump = 1'b0;
			   Mret_taken = 1'b0;
			   IsCSR = 1'b1;
			end 

			default:
			begin
			   RegWrite = 1'bx;
	   		   ImmSrc = 3'bxxx;
		       ALUSrc = 1'bx;
		       MemWrite = 1'bx;
		       ResultSrc = 2'bxx;
		       Branch = 1'bx;
		       ALUop = 3'bxxx;
		       Jump = 1'bx;
			   Mret_taken = 1'bx;
			   IsCSR = 1'bx;
			end
			endcase
		   end

	       default: begin		
		       RegWrite = 1'bx;
       		       ImmSrc = 3'bxxx;
		       ALUSrc = 1'bx;
		       MemWrite = 1'bx;
		       ResultSrc = 2'bxx;
		       Branch = 1'bx;
		       ALUop = 3'bxxx;
		       Jump = 1'bx;
			   Mret_taken = 1'bx;
			   IsCSR = 1'bx;
	       end
	       endcase
       end


endmodule 
