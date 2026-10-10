// CPU + AHB-Lite data slave, connected by the bus.
// Stage 2: one slave, HSEL tied to 1. The bus-wide HREADY is the slave's HREADYOUT (single slave, no mux needed yet).
// WAIT_CYCLES is a test input: how many wait states the slave gives the next transfer (0 = none).
// When more slaves are added, an address decoder will drive each HSEL and a mux will select HRDATA / HREADYOUT / HRESP.
module soc_top
(
    input clk, reset, interrupt_keyboard, interrupt_disk,
    input [3:0] WAIT_CYCLES
);

wire        HWRITE;
wire [1:0]  HTRANS;
wire [2:0]  HSIZE;
wire [31:0] HADDR, HWDATA, HRDATA;
wire        HREADYOUT, HRESP;
wire        HREADY = HREADYOUT;   // one slave: the bus-wide ready is just its ready

top cpu_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_keyboard(interrupt_keyboard),
    .interrupt_disk(interrupt_disk),
    .HREADY(HREADY),
    .HRDATA(HRDATA),
    .HWRITE(HWRITE),
    .HTRANS(HTRANS),
    .HSIZE(HSIZE),
    .HADDR(HADDR),
    .HWDATA(HWDATA)
);

AHB_data_memory data_slave_inst
(
    .HCLK(clk),
    .HRESETn(~reset),
    .HWRITE(HWRITE),
    .HSEL(1'b1),
    .HREADY(HREADY),
    .HTRANS(HTRANS),
    .HSIZE(HSIZE),
    .HADDR(HADDR),
    .HWDATA(HWDATA),
    .WAIT_CYCLES(WAIT_CYCLES),
    .HREADYOUT(HREADYOUT),
    .HRESP(HRESP),
    .HRDATA(HRDATA)
);

endmodule