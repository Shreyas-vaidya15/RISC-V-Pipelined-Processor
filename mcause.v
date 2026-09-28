module mcause
(
    input [31:0] csr_wdata,
    input [1:0] interrupt_ID,
    input clk, reset, interrupt_taken, mcause_write_en,
    output reg [31:0] mcause
);

reg [31:0] cause_next;

always@(*)
begin
case(interrupt_ID)
2'd1:cause_next={1'b1, 31'd7};
2'd2:cause_next={1'b1,31'd27};
default:cause_next=32'd0;
endcase
end

always@(posedge clk or posedge reset)
begin

if(reset)
begin
mcause <= 32'b0;
end

else if(interrupt_taken)
begin
    mcause <= cause_next;
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