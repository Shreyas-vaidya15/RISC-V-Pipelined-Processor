module mie
(
    input clk, reset, interrupt_keyboard_taken, interrupt_disk_taken, mret_taken, mie_write_en, csr_wdata_b0,
    output reg mie_out
);

always@(posedge clk or posedge reset)
begin

if(reset)
begin
mie_out <= 1'b1;
end

else if(interrupt_keyboard_taken || interrupt_disk_taken)
begin
mie_out <= 1'b0;
end

else if(mie_write_en)
begin
    mie_out <= csr_wdata_b0;
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