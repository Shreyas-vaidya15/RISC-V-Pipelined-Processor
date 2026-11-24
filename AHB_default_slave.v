// Default slave: selected by the decoder when no other slave claims the address.
// Every real transfer (HSEL && HTRANS[1] && HREADY) gets the two-cycle ERROR response.
// No memory, no saved address, no wait states. HRDATA is always 0.
module AHB_default_slave
(
    input HCLK,
    input HRESETn,
    input HSEL,
    input HREADY,
    input [1:0] HTRANS,
    output HREADYOUT,
    output HRESP,
    output [31:0] HRDATA
);

localparam [1:0] S_OKAY = 2'd0,
                 S_ERR1 = 2'd2,
                 S_ERR2 = 2'd3;

reg [1:0] state, next_state;

// ---------------- trigger ----------------
wire accepted = HSEL && HTRANS[1] && HREADY;

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

    S_OKAY: if(accepted) next_state = S_ERR1;

    S_ERR1: next_state = S_ERR2;

    // the next address phase is on the bus in this cycle: if it is also for this slave, start another error
    S_ERR2: next_state = accepted ? S_ERR1 : S_OKAY;

    default: next_state = S_OKAY;

    endcase
end

// ---------------- outputs (depend only on the state) ----------------
assign HREADYOUT = (state == S_OKAY) || (state == S_ERR2);
assign HRESP     = (state == S_ERR1) || (state == S_ERR2);
assign HRDATA    = 32'h0;

endmodule