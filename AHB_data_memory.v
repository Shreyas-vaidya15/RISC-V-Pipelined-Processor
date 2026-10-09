module AHB_data_memory
(
    input HCLK,
    input HRESETn,
    input HWRITE,
    input HSEL,
    input HREADY,
    input [1:0] HTRANS,
    input [2:0] HSIZE,
    input [31:0] HADDR,
    input [31:0] HWDATA,
    output HREADYOUT,
    output HRESP,
    output [31:0] HRDATA
);

reg write_dp;
reg valid_dp;
reg [1:0] size_dp;
reg [31:0] addr_dp;

always@(posedge HCLK or negedge HRESETn)
begin

    if(!HRESETn)
    begin
        write_dp <= 1'b0;
        valid_dp <= 1'b0;
        size_dp <= 2'b0;
        addr_dp <= 32'b0;
    end

    else if(HREADY)
    begin
        write_dp <= HWRITE;
        valid_dp <= HSEL && HTRANS[1];
        size_dp <= HSIZE[1:0];
        addr_dp <= HADDR;
    end

end

assign HREADYOUT = 1'b1;
assign HRESP = 1'b0;

data_memory data_memory_inst
(
    .clk(HCLK),
    .addr(addr_dp),
    .we(valid_dp && write_dp),
    .width(size_dp),
    .wdata(HWDATA),
    .rdata(HRDATA)
);


endmodule