// Address decoder + response mux for the shared AHB-Lite bus. Two real slaves and a default slave.
// Windows are 2**REGION_BITS bytes (4 KB), so the decoder only compares the upper address bits.
// A slave's window must be at least as big as the memory inside it.
// hsel_dp (the slave whose DATA phase is on the bus) is registered and updated only when HREADY = 1.
// It resets to the default slave, which answers OKAY / ready while idle.
module AHB_interconnect #(parameter [31:0] IMEM_BASE = 32'h00000000,
                          parameter [31:0] DMEM_BASE = 32'h10000000,
                          parameter REGION_BITS = 12)
(
    input HCLK,
    input HRESETn,
    input [31:0] HADDR,

    // address phase: which slave is addressed
    output HSEL_IMEM,
    output HSEL_DMEM,
    output HSEL_DEF,

    // responses from the slaves
    input IMEM_HREADYOUT, IMEM_HRESP,
    input [31:0] IMEM_HRDATA,
    input DMEM_HREADYOUT, DMEM_HRESP,
    input [31:0] DMEM_HRDATA,
    input DEF_HREADYOUT, DEF_HRESP,
    input [31:0] DEF_HRDATA,

    // bus-wide response to the master and to every slave
    output HREADY,
    output HRESP,
    output [31:0] HRDATA
);

// ---------------- decoder ----------------
wire match_imem = ((HADDR >> REGION_BITS) == (IMEM_BASE >> REGION_BITS));
wire match_dmem = ((HADDR >> REGION_BITS) == (DMEM_BASE >> REGION_BITS));

assign HSEL_IMEM = match_imem;
assign HSEL_DMEM = match_dmem & ~match_imem;          // never two selects at once
assign HSEL_DEF  = ~(match_imem | match_dmem);        // nobody claims the address

// ---------------- data-phase select (registered, only when HREADY = 1) ----------------
reg dp_imem, dp_dmem, dp_def;

always@(posedge HCLK or negedge HRESETn)
begin
    if(!HRESETn)
    begin
        dp_imem <= 1'b0;
        dp_dmem <= 1'b0;
        dp_def  <= 1'b1;
    end

    else if(HREADY)
    begin
        dp_imem <= HSEL_IMEM;
        dp_dmem <= HSEL_DMEM;
        dp_def  <= HSEL_DEF;
    end
end

// ---------------- response mux ----------------
assign HREADY = dp_imem ? IMEM_HREADYOUT :
                dp_dmem ? DMEM_HREADYOUT :
                          DEF_HREADYOUT;

assign HRESP  = dp_imem ? IMEM_HRESP :
                dp_dmem ? DMEM_HRESP :
                          DEF_HRESP;

assign HRDATA = dp_imem ? IMEM_HRDATA :
                dp_dmem ? DMEM_HRDATA :
                          DEF_HRDATA;

endmodule