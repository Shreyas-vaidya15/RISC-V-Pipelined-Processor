module load_extend
(
    input [2:0] Funct3,
    input [31:0] HRDATA,
    output reg [31:0] ReadData
);

always @(*) 
begin
    case (Funct3)
        3'b000: ReadData = {{24{HRDATA[7]}},  HRDATA[7:0]};   // lb  - sign-extend byte
        3'b001: ReadData = {{16{HRDATA[15]}}, HRDATA[15:0]};  // lh  - sign-extend half
        3'b010: ReadData = HRDATA;                              // lw  - full word
        3'b100: ReadData = {24'b0, HRDATA[7:0]};                // lbu - zero-extend byte
        3'b101: ReadData = {16'b0, HRDATA[15:0]};               // lhu - zero-extend half
        default: ReadData = HRDATA;
    endcase
end

endmodule