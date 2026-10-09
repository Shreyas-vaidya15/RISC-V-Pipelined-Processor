module AHB_master_CPU_interface
(
    input IsLoad_MEM,
    input MemWrite_MEM,
    input [1:0] Width_MEM,
    input [31:0] ALUResult_MEM,
    input [31:0] RD2_WB,
    output HWRITE,
    output [1:0] HTRANS,
    output [2:0] HSIZE,
    output [31:0] HADDR,
    output [31:0] HWDATA
);

assign HWRITE = MemWrite_MEM;
assign HTRANS = (IsLoad_MEM | MemWrite_MEM) ? 2'b10 : 2'b00;
assign HSIZE = {1'b0, Width_MEM};
assign HADDR = ALUResult_MEM;
assign HWDATA = RD2_WB;


endmodule