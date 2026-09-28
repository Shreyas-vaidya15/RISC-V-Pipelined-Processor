module mepc
(
    input clk, reset, interrupt_taken, mepc_write_en,
    input [31:0] csr_wdata,
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

else if(mepc_write_en)
begin
MEPC_OUT <= csr_wdata;
end

else
begin
MEPC_OUT <= MEPC_OUT;
end

end

endmodule