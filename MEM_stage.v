module MEM_stage #(parameter DEPTH = 64)
(
    input clk, MemWrite,
    input [1:0] Width,
    input [2:0] Funct3,
    input [31:0] RD2, ALUResult,
    output reg [31:0] ReadData
);

wire [31:0] rdata;

data_memory #(.DEPTH(DEPTH)) data_memory_inst
(
    .clk(clk),
    .addr(ALUResult),
    .we(MemWrite),
    .width(Width),
    .wdata(RD2),
    .rdata(rdata)
);

always @(*) begin
    case (Funct3)
        3'b000: ReadData = {{24{rdata[7]}},  rdata[7:0]};   // lb  - sign-extend byte
        3'b001: ReadData = {{16{rdata[15]}}, rdata[15:0]};  // lh  - sign-extend half
        3'b010: ReadData = rdata;                              // lw  - full word
        3'b100: ReadData = {24'b0, rdata[7:0]};                // lbu - zero-extend byte
        3'b101: ReadData = {16'b0, rdata[15:0]};               // lhu - zero-extend half
        default: ReadData = rdata;
    endcase
end
endmodule