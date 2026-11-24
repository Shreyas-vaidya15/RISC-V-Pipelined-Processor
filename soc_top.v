// CPU + one shared AHB-Lite bus + two slaves (instruction memory, data memory) + a default slave.
// The CPU is the only master: fetch and load/store share the bus (load/store wins).
// Memory map (4 KB windows, decoded on HADDR[31:12]):
//   instruction memory  IMEM_BASE = 0x0000_0000   (later: boot ROM here, instruction memory moves)
//   data memory         DMEM_BASE = 0x1000_0000
//   everything else     default slave (ERROR response)
// WAIT_CYCLES is a test input: how many wait states the data slave gives the next transfer (0 = none).
module soc_top #(parameter [31:0] IMEM_BASE = 32'h00000000,
                 parameter [31:0] DMEM_BASE = 32'h10000000)
(
    input clk, reset, interrupt_keyboard, interrupt_disk,
    input [3:0] WAIT_CYCLES
);

// ---------------- the bus ----------------
wire        HWRITE;
wire [1:0]  HTRANS;
wire [2:0]  HSIZE;
wire [31:0] HADDR, HWDATA, HRDATA;
wire        HREADY, HRESP;

wire HSEL_IMEM, HSEL_DMEM, HSEL_DEF;

wire        IMEM_HREADYOUT, IMEM_HRESP;
wire [31:0] IMEM_HRDATA;
wire        DMEM_HREADYOUT, DMEM_HRESP;
wire [31:0] DMEM_HRDATA;
wire        DEF_HREADYOUT, DEF_HRESP;
wire [31:0] DEF_HRDATA;

top #(.IMEM_BASE(IMEM_BASE)) cpu_inst
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
    .HWDATA(HWDATA)
);

AHB_interconnect #(.IMEM_BASE(IMEM_BASE), .DMEM_BASE(DMEM_BASE)) interconnect_inst
(
    .HCLK(clk),
    .HRESETn(~reset),
    .HADDR(HADDR),
    .HSEL_IMEM(HSEL_IMEM),
    .HSEL_DMEM(HSEL_DMEM),
    .HSEL_DEF(HSEL_DEF),
    .IMEM_HREADYOUT(IMEM_HREADYOUT), .IMEM_HRESP(IMEM_HRESP), .IMEM_HRDATA(IMEM_HRDATA),
    .DMEM_HREADYOUT(DMEM_HREADYOUT), .DMEM_HRESP(DMEM_HRESP), .DMEM_HRDATA(DMEM_HRDATA),
    .DEF_HREADYOUT(DEF_HREADYOUT),   .DEF_HRESP(DEF_HRESP),   .DEF_HRDATA(DEF_HRDATA),
    .HREADY(HREADY),
    .HRESP(HRESP),
    .HRDATA(HRDATA)
);

AHB_data_memory #(.BASE(DMEM_BASE)) data_slave_inst
(
    .HCLK(clk),
    .HRESETn(~reset),
    .HWRITE(HWRITE),
    .HSEL(HSEL_DMEM),
    .HREADY(HREADY),
    .HTRANS(HTRANS),
    .HSIZE(HSIZE),
    .HADDR(HADDR),
    .HWDATA(HWDATA),
    .WAIT_CYCLES(WAIT_CYCLES),
    .HREADYOUT(DMEM_HREADYOUT),
    .HRESP(DMEM_HRESP),
    .HRDATA(DMEM_HRDATA)
);

AHB_inst_memory #(.BASE(IMEM_BASE)) inst_slave_inst
(
    .HCLK(clk),
    .HRESETn(~reset),
    .HWRITE(HWRITE),
    .HSEL(HSEL_IMEM),
    .HREADY(HREADY),
    .HTRANS(HTRANS),
    .HSIZE(HSIZE),
    .HADDR(HADDR),
    .HWDATA(HWDATA),
    .HREADYOUT(IMEM_HREADYOUT),
    .HRESP(IMEM_HRESP),
    .HRDATA(IMEM_HRDATA)
);

AHB_default_slave default_slave_inst
(
    .HCLK(clk),
    .HRESETn(~reset),
    .HSEL(HSEL_DEF),
    .HREADY(HREADY),
    .HTRANS(HTRANS),
    .HREADYOUT(DEF_HREADYOUT),
    .HRESP(DEF_HRESP),
    .HRDATA(DEF_HRDATA)
);

endmodule