// CPU + AHB-Lite data slave + AHB-Lite instruction slave.
// Stage 1 of putting the instruction memory on the bus: the instruction memory has its OWN bus (IH* signals),
// separate from the data bus. Fetch is read-only: HWRITE = 0, word size, no write data.
// WAIT_CYCLES is a test input: how many wait states the data slave gives the next transfer (0 = none).
module soc_top
(
    input clk, reset, interrupt_keyboard, interrupt_disk,
    input [3:0] WAIT_CYCLES
);

// ---------------- data bus ----------------
wire        HWRITE;
wire [1:0]  HTRANS;
wire [2:0]  HSIZE;
wire [31:0] HADDR, HWDATA, HRDATA;
wire        HREADYOUT, HRESP;
wire        HREADY = HREADYOUT;   // one slave: the bus-wide ready is just its ready

// ---------------- instruction bus ----------------
wire [1:0]  IHTRANS;
wire [31:0] IHADDR, IHRDATA;
wire        IHREADYOUT, IHRESP;
wire        IHREADY = IHREADYOUT;

top cpu_inst
(
    .clk(clk),
    .reset(reset),
    .interrupt_keyboard(interrupt_keyboard),
    .interrupt_disk(interrupt_disk),
    .HREADY(HREADY),
    .HRESP(HRESP),
    .HRDATA(HRDATA),
    .HWRITE(HWRITE),
    .HTRANS(HTRANS),
    .HSIZE(HSIZE),
    .HADDR(HADDR),
    .HWDATA(HWDATA),
    .IHRDATA(IHRDATA),
    .IHTRANS(IHTRANS),
    .IHADDR(IHADDR)
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

AHB_inst_memory inst_slave_inst
(
    .HCLK(clk),
    .HRESETn(~reset),
    .HWRITE(1'b0),
    .HSEL(1'b1),
    .HREADY(IHREADY),
    .HTRANS(IHTRANS),
    .HSIZE(3'b010),
    .HADDR(IHADDR),
    .HWDATA(32'b0),
    .HREADYOUT(IHREADYOUT),
    .HRESP(IHRESP),
    .HRDATA(IHRDATA)
);

endmodule