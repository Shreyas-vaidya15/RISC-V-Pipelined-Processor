module mepc
(
    input clk, reset, interrupt_taken,
    input [31:0] EX_MEPC_IN,
    output reg [31:0] MEPC_OUT
);

always@(posedge clk or posedge reset)

begin

if(reset)
begin
MEPC_OUT <= 32'b0;
end

else if(interrupt_taken)
begin
MEPC_OUT <= EX_MEPC_IN;
end

else
begin
MEPC_OUT <= MEPC_OUT;
end

end

endmodule