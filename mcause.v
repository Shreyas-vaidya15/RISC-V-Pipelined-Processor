module mcause
(
    input [31:0] csr_wdata,
    input clk, reset, interrupt_keyboard_taken, interrupt_disk_taken, mcause_write_en,
    output reg [31:0] mcause
);

always@(posedge clk or posedge reset)
begin

if(reset)
begin
mcause <= 32'b0;
end

else if(interrupt_disk_taken)
begin
    mcause <= {1'b1, 31'd27};
end

else if(interrupt_keyboard_taken)
begin
mcause <= {1'b1, 31'd7};
end

else if(mcause_write_en)
begin
    mcause <= csr_wdata;
end
else
begin
mcause <= mcause;
end

end

endmodule