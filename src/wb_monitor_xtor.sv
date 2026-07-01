// ----------------------------------------------------------------------------
// Wishbone Monitor transactor (integration)
//
// Integrates the SV interface (egress FIFO + task API) with the core monitor.
// The HVL side reaches the task API via the inner interface instance: u_if.
// Public Wishbone taps use bare names (all inputs -- the monitor drives nothing).
// ----------------------------------------------------------------------------
module wb_monitor_xtor #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int MON_WIDTH  = (ADDR_WIDTH + DATA_WIDTH + (DATA_WIDTH/8) + 1 + 1)
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // Wishbone (protocol) signals -- passively observed
        input  wire [ADDR_WIDTH-1:0]    adr,
        input  wire [DATA_WIDTH-1:0]    dat_w,
        input  wire [DATA_WIDTH-1:0]    dat_r,
        input  wire                     cyc,
        input  wire                     err,
        input  wire [DATA_WIDTH/8-1:0]  sel,
        input  wire                     stb,
        input  wire                     ack,
        input  wire                     we
    );

    // RV egress channel between core and interface
    wire [MON_WIDTH-1:0]  mon_dat;
    wire                  mon_valid;
    wire                  mon_ready;

    // Only ADDR_WIDTH/DATA_WIDTH are overridden so the interface specialization
    // matches a `virtual wb_monitor_xtor_if #(ADDR_WIDTH, DATA_WIDTH)` handle.
    wb_monitor_xtor_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_if (
        .clock(clock),
        .reset(reset),
        .mon_dat(mon_dat),
        .mon_valid(mon_valid),
        .mon_ready(mon_ready)
    );

    wb_monitor_xtor_core #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MON_WIDTH(MON_WIDTH)
    ) u_core (
        .clock(clock),
        .reset(reset),
        .adr(adr),
        .dat_w(dat_w),
        .dat_r(dat_r),
        .cyc(cyc),
        .err(err),
        .sel(sel),
        .stb(stb),
        .ack(ack),
        .we(we),
        .mon_dat(mon_dat),
        .mon_valid(mon_valid),
        .mon_ready(mon_ready)
    );

endmodule
