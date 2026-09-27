	module alu(
		input [31:0]  A,
		input [31:0]  B,
		input [3:0]   ALUControl,
		output reg [31:0] Result,
		output reg 	  Zero,
		output reg 	  Overflow,
		output reg 	  Carry,
		output reg 	  Negative);

	reg slt, sltu;

	always @(*) begin
		Carry = 1'b0;
		Overflow = 1'b0;
		case (ALUControl)
			4'b0000: begin
					{Carry, Result} = A + B;
					Overflow = (~A[31] & ~B[31] & Result[31]) | (A[31] & B[31] & ~Result[31]);
				end
			4'b0001: begin
					{Carry, Result} = A - B;
						Overflow = (A[31] & ~B[31] & ~Result[31]) | (~A[31] & B[31] & Result[31]);
				end
			4'b0010: Result = A & B;
			4'b0011: Result = A | B;
			4'b0100: Result = A ^ B;
			4'b0101: begin
						slt = (A[31] == B[31]) ? (A<B) : A[31];
					Result = {31'b0, slt};
				end
			4'b0110: begin
					sltu = A < B;
					Result = {31'b0, sltu};
				end
			4'b0111: Result = {A[31:12], 12'b0};
			4'b1000: {Carry, Result} = A + {B[31:12], 12'b0};
			4'b1001: Result = {B[31:12], 12'b0};
			4'b1010: Result = A <<< B[4:0];
			4'b1011: Result = $signed(A) >>> B[4:0];
			4'b1100: Result = A >> B[4:0];
			4'b1101: Result = ~A & B;
			default : Result = 32'bx;		 
		endcase
		Zero = ~|Result;
		Negative = Result[31];

	end

	endmodule

