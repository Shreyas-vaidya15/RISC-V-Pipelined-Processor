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
    input [3:0] WAIT_CYCLES,
    output reg HREADYOUT,
    output HRESP,
    output [31:0] HRDATA
);

reg write_dp;
reg valid_dp;
reg [1:0] size_dp;
reg [31:0] addr_dp;
reg [3:0] wait_cnt;   
always@(posedge HCLK or negedge HRESETn)
begin
    if(!HRESETn)
    begin
        write_dp <= 1'b0;
        valid_dp <= 1'b0;
        size_dp <= 2'b0;
        addr_dp <= 32'b0;
        wait_cnt <= 4'd0;
        HREADYOUT <= 1'b1;
    end

    else if(HREADY)
    begin
        write_dp <= HWRITE;
        valid_dp <= HSEL && HTRANS[1];
        size_dp <= HSIZE[1:0];
        addr_dp <= HADDR;

        if(HSEL && HTRANS[1] && WAIT_CYCLES != 4'd0)
        begin
            HREADYOUT <= 1'b0;
            wait_cnt <= WAIT_CYCLES - 4'd1;
        end
        else
        begin
            HREADYOUT <= 1'b1;
        end
    end

    else if(!HREADYOUT)
    begin
        if(wait_cnt == 4'd0)
            HREADYOUT <= 1'b1;
        else
            wait_cnt <= wait_cnt - 4'd1;
    end
end

assign HRESP = 1'b0;

wire [31:0] rdata_mem;

data_memory data_memory_inst
(
    .clk(HCLK),
    .addr(addr_dp),
    .we(valid_dp && write_dp && HREADYOUT),
    .width(size_dp),
    .wdata(HWDATA),
    .rdata(rdata_mem)
);

assign HRDATA = HREADYOUT ? rdata_mem : 32'hBAD0BAD0;

endmodule