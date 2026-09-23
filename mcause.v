module mcause
(
    input clk, reset, interrupt_taken,
    output reg [31:0] mcause
);

always@(posedge clk or posedge reset)
begin

if(reset)
begin
mcause <= 32'b0;
end

else if(interrupt_taken)
begin
mcause <= {1'b1, 31'd7};
end

else
begin
mcause <= mcause;
end

end

endmodule