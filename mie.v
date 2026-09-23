module mie
(
    input clk, reset, interrupt_taken, mret_taken,
    output reg mie_out
);

always@(posedge clk or posedge reset)
begin

if(reset)
begin
mie_out <= 1'b1;
end

else if(interrupt_taken)
begin
mie_out <= 1'b0;
end

else if (mret_taken)
begin
    mie_out <= 1'b1;
end

else
begin
mie_out <= mie_out;
end
end

endmodule