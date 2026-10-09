// CPU + AHB-Lite data slave, connected by the bus.
// Stage 1 (perfect case): one slave, HSEL tied to 1, HREADY tied to 1, HRESP / HREADYOUT not used yet.
// When more slaves are added, an address decoder will drive each HSEL and a mux will select HRDATA / HREADYOUT / HRESP.
module soc_top
(
    input clk, reset, interrupt_keyboard, interrupt_disk
);

wire        HWRITE;
wire [1:0]  HTRANS;
wire [2:0]  HSIZE;
wire [31:0] HADDR, HWDATA, HRDATA;
wire        HREADYOUT, HRESP;

top cpu_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_keyboard(interrupt_keyboard),
    .interrupt_disk(interrupt_disk),
    .HRDATA(HRDATA),
    .HWRITE(HWRITE),
    .HTRANS(HTRANS),
    .HSIZE(HSIZE),
    .HADDR(HADDR),
    .HWDATA(HWDATA)
);

AHB_data_memory data_slave_inst   // rename to AHB_slave_data_memory here if you renamed the module
(
    .HCLK(clk),
    .HRESETn(~reset),
    .HWRITE(HWRITE),
    .HSEL(1'b1),
    .HREADY(1'b1),
    .HTRANS(HTRANS),
    .HSIZE(HSIZE),
    .HADDR(HADDR),
    .HWDATA(HWDATA),
    .HREADYOUT(HREADYOUT),
    .HRESP(HRESP),
    .HRDATA(HRDATA)
);

endmodule