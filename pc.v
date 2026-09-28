module pc(
	output reg [31:0] PC,
	input [31:0] PCNext, pc_mtvec_mcause,
	input clk, reset, Stall, interrupt_taken
);

always @(posedge clk or posedge reset) begin
	if(reset)
		PC <= 32'b0;
	else if(interrupt_taken)
	begin
		PC <= pc_mtvec_mcause;
	end
	else if(Stall)
		PC <= PC;
	else
		PC <= PCNext;
end

endmodule
