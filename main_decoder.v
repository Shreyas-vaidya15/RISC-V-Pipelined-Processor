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
	output reg Illegal_opcode,
	output reg illegal_funct3,
	output reg IsLoad,
	output reg Illegal_System_Imm,
	output reg Ecall,
	output reg Ebreak,
	input [11:0] System_Imm,
	input [6:0] op,
	input [2:0] funct3
);

always @(*) begin
	Illegal_opcode = 1'b0;
	illegal_funct3 = 1'b0;
	IsLoad = 1'b0;
	Illegal_System_Imm = 1'b0;
	Ecall = 1'b0;
	Ebreak = 1'b0;
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
			   IsLoad = 1'b1;
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
				case(System_Imm)
				12'h000:
				begin
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
					Ecall = 1'b1;
				end

				12'h001:
				begin
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
					Ebreak = 1'b1;
				end

				12'h302:
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

				default:
				begin
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
					Illegal_System_Imm = 1'b1;
				end
				endcase
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
			   illegal_funct3 = 1'b1;
			end
			endcase
		   end

	       default: begin		
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
			   Illegal_opcode = 1'b1;
	       end
	       endcase
       end


endmodule 
