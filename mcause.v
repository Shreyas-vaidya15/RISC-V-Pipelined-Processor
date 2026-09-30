module mcause
(
    input [31:0] csr_wdata,
    input [1:0] interrupt_ID,
    input clk, reset, interrupt_taken, mcause_write_en, exception_taken,
    output reg [31:0] mcause
);

wire [31:0] exception_cause_next;
reg [31:0] interrupt_cause_next;

always@(*)
begin
case(interrupt_ID)
2'd1 : interrupt_cause_next = {1'b1, 31'd7};
2'd2 : interrupt_cause_next = {1'b1,31'd27};
default : interrupt_cause_next = 32'd0;
endcase
end

assign exception_cause_next = 32'd2;

always@(posedge clk or posedge reset)
begin

if(reset)
begin
mcause <= 32'b0;
end

else if(interrupt_taken)
begin
    mcause <= interrupt_cause_next;
end

else if(exception_taken)
begin
    mcause <= exception_cause_next;    
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