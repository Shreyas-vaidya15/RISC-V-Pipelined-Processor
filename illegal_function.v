module illegal_function
(
    input [6:0] funct7, op,
    input [2:0] funct3,
    output reg illegal_funct7, illegal_funct3
);

always@(*)
begin

    illegal_funct7 = 1'b0;
    illegal_funct3 = 1'b0;

    case(op)

    7'b0110011:  // R-type
    begin
        if(funct7 == 7'd32)
        begin
            if(funct3 != 3'd0 && funct3 != 3'd5)
            begin
                illegal_funct3 = 1'b1;
            end
        end

        else if(funct7 != 7'd0)
        begin
            illegal_funct7 = 1'b1;
        end
    end

    7'b0000011:  // loads
    begin
        if(funct3 == 3'd3 || funct3 == 3'd6 || funct3 == 3'd7)
        begin
            illegal_funct3 = 1'b1;
        end
    end

    7'b0010011:  // I-type ALU: only the shifts have a funct7 field
    begin
        if(funct3 == 3'd1)  // slli
        begin
            if(funct7 != 7'd0)
            begin
                illegal_funct7 = 1'b1;
            end
        end

        else if(funct3 == 3'd5)  // srli / srai
        begin
            if(funct7 != 7'd0 && funct7 != 7'd32)
            begin
                illegal_funct7 = 1'b1;
            end
        end
    end

    7'b0100011:  // stores: only sb, sh, sw
    begin
        if(funct3 > 3'd2)
        begin
            illegal_funct3 = 1'b1;
        end
    end

    7'b1100011:  // branches
    begin
        if(funct3 == 3'd2 || funct3 == 3'd3)
        begin
            illegal_funct3 = 1'b1;
        end
    end

    7'b1100111:  // jalr
    begin
        if(funct3 != 3'd0)
        begin
            illegal_funct3 = 1'b1;
        end
    end

    default: ;
    endcase
end

endmodule