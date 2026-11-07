module csr_counters
(
    input clk,
    input reset,
    input mcycle_wr_lo, mcycle_wr_hi, minstret_wr_lo, minstret_wr_hi,
    input [31:0] csr_wdata,
    input retire,
    input mem_valid,
    output [31:0] mcycle_lo, mcycle_hi, minstret_lo, minstret_hi
);

reg [63:0] cycle_r;
reg [63:0] instret_r;

wire [63:0] cycle_inc = cycle_r + 64'd1;

always@(posedge clk or posedge reset)
begin
    if(reset)
        cycle_r <= 64'b0;
    else
    begin
        cycle_r[31:0]  <= mcycle_wr_lo ? csr_wdata : cycle_inc[31:0];
        cycle_r[63:32] <= mcycle_wr_hi ? csr_wdata : cycle_inc[63:32];
    end
end

assign mcycle_lo = cycle_r[31:0];
assign mcycle_hi = cycle_r[63:32];

wire [1:0]  in_flight = {1'b0, mem_valid} + {1'b0, retire};
wire [63:0] visible   = instret_r + {62'b0, in_flight};

wire minstret_write = minstret_wr_lo | minstret_wr_hi;

wire [63:0] new_visible = minstret_wr_lo ? {visible[63:32], csr_wdata} :
                          minstret_wr_hi ? {csr_wdata, visible[31:0]}  : visible;

wire [63:0] written_value = new_visible - {63'b0, mem_valid} - 64'd1;

always@(posedge clk or posedge reset)
begin
    if(reset)
        instret_r <= 64'b0;
    else if(minstret_write)
        instret_r <= written_value;
    else
        instret_r <= instret_r + {63'b0, retire};
end

assign minstret_lo = visible[31:0];
assign minstret_hi = visible[63:32];

endmodule