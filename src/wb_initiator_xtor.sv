// ----------------------------------------------------------------------------
// Wishbone Initiator transactor (integration)
//
// Integrates the SV interface (FIFOs + task API) with the core transactor.
// The HVL side reaches the task API via the inner interface instance: u_if.
// Public Wishbone pins use bare names (adr/dat_w/dat_r/...) -- kit convention D6.
// ----------------------------------------------------------------------------
module wb_initiator_xtor #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int REQ_WIDTH  = (ADDR_WIDTH + DATA_WIDTH + (DATA_WIDTH/8) + 1),
        parameter int RSP_WIDTH  = (DATA_WIDTH + 1)
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // Wishbone initiator (protocol) signals
        output wire [ADDR_WIDTH-1:0]    adr,
        output wire [DATA_WIDTH-1:0]    dat_w,
        input  wire [DATA_WIDTH-1:0]    dat_r,
        output wire                     cyc,
        input  wire                     err,
        output wire [DATA_WIDTH/8-1:0]  sel,
        output wire                     stb,
        input  wire                     ack,
        output wire                     we
    );

    // RV channels between interface and core
    wire [REQ_WIDTH-1:0]  req_dat;
    wire                  req_valid;
    wire                  req_ready;
    wire [RSP_WIDTH-1:0]  rsp_dat;
    wire                  rsp_valid;
    wire                  rsp_ready;

    // Only ADDR_WIDTH/DATA_WIDTH are overridden so the interface specialization
    // matches a `virtual wb_initiator_xtor_if #(ADDR_WIDTH, DATA_WIDTH)` handle
    // (the derived REQ_WIDTH/RSP_WIDTH/DEPTH take their in-interface defaults).
    wb_initiator_xtor_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_if (
        .clock(clock),
        .reset(reset),
        .req_dat(req_dat),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .rsp_dat(rsp_dat),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready)
    );

    wb_initiator_xtor_core #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .REQ_WIDTH(REQ_WIDTH),
        .RSP_WIDTH(RSP_WIDTH)
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
        .req_dat(req_dat),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .rsp_dat(rsp_dat),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready)
    );

endmodule
