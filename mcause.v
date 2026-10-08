module mcause
(
    input [31:0] csr_wdata,
    input [1:0] interrupt_ID,
    input clk, reset, interrupt_taken, mcause_write_en, exception_taken, misaligned, misaligned_store, Ecall, Ebreak, instruction_address_misalign, load_store_access_fault, IsLoad, instruction_access_fault,
    output reg [31:0] mcause
);

reg [31:0] exception_cause_next;
reg [31:0] interrupt_cause_next;

always@(*)
begin
case(interrupt_ID)
2'd1, 2'd2 : interrupt_cause_next = {1'b1, 31'd11};
default : interrupt_cause_next = 32'd0;
endcase
end

always@(*)
begin
    if(misaligned)
        begin
            if(misaligned_store)
                begin
                    exception_cause_next = 32'd6;
                end

            else
                begin
                    exception_cause_next = 32'd4;
                end
        end

    else if(load_store_access_fault)
        begin

            if(IsLoad)
                begin
                    exception_cause_next = 32'd5;
                end

            else
                begin
                    exception_cause_next = 32'd7;
                end
        end

    else if(instruction_address_misalign)
        begin
            exception_cause_next = 32'd0;
        end

    else if(instruction_access_fault)
    begin
        exception_cause_next = 32'd1;
    end

    else if(Ecall)
        begin
            exception_cause_next = 32'd11;
        end

    else if(Ebreak)
        begin
            exception_cause_next = 32'd3;
        end

    else
        begin
            exception_cause_next = 32'd2;
        end

end

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