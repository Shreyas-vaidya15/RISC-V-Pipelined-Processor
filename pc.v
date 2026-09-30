module pc(
	output reg [31:0] PC,
	input [31:0] PCNext, pc_mtvec_mcause,
	input clk, reset, Stall, interrupt_taken, exception_taken
);

always @(posedge clk or posedge reset) begin
	if(reset)
	begin
		PC <= 32'b0;
	end

	else if(interrupt_taken)
	begin
		PC <= pc_mtvec_mcause;
	end

	else if(exception_taken)
	begin
		PC <= pc_mtvec_mcause;
	end
	
	else if(Stall)
	begin
		PC <= PC;
	end

	else
	begin
		PC <= PCNext;
	end
end

endmodule
