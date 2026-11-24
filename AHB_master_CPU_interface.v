// AHB-Lite master of the CPU. One bus, two requesters: a load/store in MEM and the instruction fetch.
// This module is the arbiter: a load/store in MEM wins, the fetch waits.
// The fetch is presented only when HREADY = 1, so an unaccepted fetch address never has to be held.
// A load/store address is held by the frozen pipeline while HREADY = 0.
//
// dp_data  : the transfer in its data phase is a load/store
// dp_fetch : the transfer in its data phase is an instruction fetch
// Both are updated only when HREADY = 1 (same as the slaves' saved address phase).
module AHB_master_CPU_interface
(
    input clk, reset,
    input IsLoad_MEM,
    input MemWrite_MEM,
    input HRESP,
    input HREADY,
    input [1:0] Width_MEM,
    input [31:0] ALUResult_MEM,
    input [31:0] RD2_WB,
    input fetch_req,                 // IF_stage wants to send a fetch address
    input [31:0] HADDR_fetch,
    output HWRITE,
    output [1:0] HTRANS,
    output [2:0] HSIZE,
    output [31:0] HADDR,
    output [31:0] HWDATA,
    output fetch_grant,              // the fetch address is on the bus this cycle
    output reg dp_data,
    output reg dp_fetch
);

wire ls_req = IsLoad_MEM | MemWrite_MEM;

// last cycle of the ERROR response of a LOAD/STORE: the next address (load/store or fetch) is cancelled.
// After a fetch error nothing is cancelled.
wire cancel = HRESP & HREADY & dp_data;

assign fetch_grant = fetch_req & ~ls_req & HREADY & ~cancel & ~reset;   // ~reset: the bus is IDLE while reset is high

assign HTRANS = ls_req ? (cancel ? 2'b00 : 2'b10) :
                         (fetch_grant ? 2'b10 : 2'b00);

assign HADDR  = ls_req ? ALUResult_MEM : HADDR_fetch;
assign HWRITE = ls_req & MemWrite_MEM;
assign HSIZE  = ls_req ? {1'b0, Width_MEM} : 3'b010;     // fetch = word
assign HWDATA = RD2_WB;

always@(posedge clk or posedge reset)
begin
    if(reset)
    begin
        dp_data  <= 1'b0;
        dp_fetch <= 1'b0;
    end

    else if(HREADY)
    begin
        dp_data  <= HTRANS[1] & ls_req;
        dp_fetch <= HTRANS[1] & ~ls_req;
    end
end

endmodule