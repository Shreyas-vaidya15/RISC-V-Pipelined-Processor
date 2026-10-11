module AHB_data_memory #(parameter DEPTH = 64)   // DEPTH is in WORDS; passed down to data_memory so the size lives in one place
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
    output HREADYOUT,
    output HRESP,
    output reg [31:0] HRDATA
);

// ---------------- states ----------------
// OKAY : ready, HRESP = 0
// WAIT : inserting wait states, HREADYOUT = 0, HRESP = 0 (still OKAY on the response wires)
// ERR1 : first error cycle,  HRESP = 1, HREADYOUT = 0
// ERR2 : second error cycle, HRESP = 1, HREADYOUT = 1
localparam [1:0] S_OKAY = 2'd0,
                 S_WAIT = 2'd1,
                 S_ERR1 = 2'd2,
                 S_ERR2 = 2'd3;

reg [1:0] state, next_state;
reg [3:0] wait_cnt;

// address-phase info saved for the data phase
reg write_dp;
reg valid_dp;
reg bad_dp;          // the transfer now in its data phase had an out-of-range address
reg [1:0] size_dp;
reg [31:0] addr_dp;

// ---------------- trigger (looks at the LIVE address phase, HADDR, not addr_dp) ----------------
wire accepted     = HSEL && HTRANS[1] && HREADY;
wire out_of_range = (HADDR >= DEPTH * 4);          // start address only: misaligned accesses never get here
wire bad_transfer = accepted && out_of_range;

// ---------------- saved address phase ----------------
always@(posedge HCLK or negedge HRESETn)
begin
    if(!HRESETn)
    begin
        write_dp <= 1'b0;
        valid_dp <= 1'b0;
        bad_dp <= 1'b0;
        size_dp <= 2'b0;
        addr_dp <= 32'b0;
    end

    else if(HREADY)
    begin
        write_dp <= HWRITE;
        valid_dp <= HSEL && HTRANS[1];
        bad_dp <= bad_transfer;
        size_dp <= HSIZE[1:0];
        addr_dp <= HADDR;
    end
end

// ---------------- wait counter (same behaviour as before) ----------------
always@(posedge HCLK or negedge HRESETn)
begin
    if(!HRESETn)
    begin
        wait_cnt <= 4'd0;
    end

    else if(state == S_OKAY && accepted && WAIT_CYCLES != 4'd0)
    begin
        wait_cnt <= WAIT_CYCLES - 4'd1;
    end

    else if(state == S_WAIT && wait_cnt != 4'd0)
    begin
        wait_cnt <= wait_cnt - 4'd1;
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
    next_state = state;                      // default: stay

    case(state)

    S_OKAY:
    begin
        if(accepted && WAIT_CYCLES != 4'd0)
            next_state = S_WAIT;             // wait first (bad_dp is latched at this same edge)
        else if(bad_transfer)
            next_state = S_ERR1;             // no wait needed: error starts right away
    end

    S_WAIT:
    begin
        if(wait_cnt == 4'd0)                 // last wait cycle
            next_state = bad_dp ? S_ERR1 : S_OKAY;
    end

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

data_memory #(.DEPTH(DEPTH)) data_memory_inst
(
    .clk(HCLK),
    .addr(addr_dp),
    .we(valid_dp && write_dp && HREADYOUT && !HRESP),   // !HRESP blocks the write in ERR2, where HREADYOUT is already 1
    .width(size_dp),
    .wdata(HWDATA),
    .rdata(rdata_mem)
);

always@(*)
begin

    if(state == S_OKAY)
    begin
        HRDATA = rdata_mem;
    end

    else if(state == S_WAIT)
    begin
        HRDATA = 32'hBAD0BAD0;
    end

    else
    begin
        HRDATA = 32'h0;
    end

end
endmodule