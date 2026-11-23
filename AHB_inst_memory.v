module AHB_inst_memory #(parameter DEPTH = 256)   // DEPTH in words, passed to inst_memory
(
    input HCLK,
    input HRESETn,
    input HWRITE,
    input HSEL,
    input HREADY,
    input [1:0] HTRANS,
    input [2:0] HSIZE,       // unused: a fetch is always a word
    input [31:0] HADDR,
    input [31:0] HWDATA,     // unused: this slave is read-only
    output HREADYOUT,
    output HRESP,
    output reg [31:0] HRDATA
);

localparam [1:0] S_OKAY = 2'd0,
                 S_ERR1 = 2'd2,
                 S_ERR2 = 2'd3;

reg [1:0] state, next_state;
reg [31:0] addr_dp;      // address saved from the address phase, used in the data phase

// ---------------- trigger ----------------
wire accepted     = HSEL && HTRANS[1] && HREADY;
wire out_of_range = (HADDR >= DEPTH * 4);
wire bad_transfer = accepted && (HWRITE || out_of_range);   // any write, or an address past the memory

// ---------------- saved address ----------------
always@(posedge HCLK or negedge HRESETn)
begin
    if(!HRESETn)
    begin
        addr_dp <= 32'd0;
    end

    else if(HREADY)
    begin
        addr_dp <= HADDR;
    end
end

// ---------------- FSM: state register ----------------
always@(posedge HCLK or negedge HRESETn)
begin
    if(!HRESETn)
    begin
        state <= S_OKAY;
    end

    else
    begin
        state <= next_state;
    end
end

// ---------------- FSM: next-state logic ----------------
always@(*)
begin
    next_state = state;

    case(state)

    S_OKAY: if(bad_transfer) next_state = S_ERR1;

    S_ERR1: next_state = S_ERR2;

    S_ERR2: next_state = S_OKAY;

    default: next_state = S_OKAY;

    endcase
end

// ---------------- outputs (depend only on the state) ----------------
assign HREADYOUT = (state == S_OKAY) || (state == S_ERR2);
assign HRESP     = (state == S_ERR1) || (state == S_ERR2);

// ---------------- memory ----------------
wire [31:0] rdata_mem;

inst_memory #(.DEPTH(DEPTH)) inst_memory_inst
(
    .addr(addr_dp),
    .data(rdata_mem)
);

always@(*)
begin
    if(state == S_OKAY)
        HRDATA = rdata_mem;
    else
        HRDATA = 32'h0;
end

endmodule