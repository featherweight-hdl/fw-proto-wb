// ----------------------------------------------------------------------------
// Wishbone Initiator transactor interface (SV, signal-level RV ports)
//
// Thin, FIFO-less bridge from the blocking task API (HVL side) to the core's
// ready/valid request/response channels:
//   - request()  : SOURCE -- drive req_dat/req_valid, await the core to accept
//   - response() : SINK   -- drive rsp_ready, await a response beat, capture it
//
// Single outstanding by construction (one blocking task pair in flight). Task
// ports use the per-instance ADDR_WIDTH/DATA_WIDTH (the kit carries no shared
// *_WIDTH_MAX; non-parameterized consumers own that).
// ----------------------------------------------------------------------------

`include "wb_xtor_macros.svh"

interface wb_initiator_xtor_if #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int REQ_WIDTH  = (ADDR_WIDTH + DATA_WIDTH + (DATA_WIDTH/8) + 1),
        parameter int RSP_WIDTH  = (DATA_WIDTH + 1),
        parameter int DEPTH      = 4
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // RV request channel: interface sources, core accepts
        output reg [REQ_WIDTH-1:0]      req_dat,
        output reg                      req_valid,
        input  wire                     req_ready,

        // RV response channel: core sources, interface accepts
        input  wire [RSP_WIDTH-1:0]     rsp_dat,
        input  wire                     rsp_valid,
        output reg                      rsp_ready
    );

    typedef `WB_INITIATOR_REQ_S(ADDR_WIDTH, DATA_WIDTH) req_s;
    typedef `WB_INITIATOR_RSP_S(ADDR_WIDTH, DATA_WIDTH) rsp_s;

    // Queue a Wishbone request
    task automatic request(
            input [ADDR_WIDTH-1:0]      adr,
            input [DATA_WIDTH-1:0]      dat,
            input [(DATA_WIDTH/8)-1:0]  sel,
            input                       we);
        req_s r;
        req_valid <= 1'b1;
        r = '{adr: adr, dat: dat, we: we, sel: sel};
        req_dat = r;

        // Wait for ack
        do begin
            @(posedge clock);
        end while (!req_valid || !req_ready);
        req_valid <= 1'b0;
        rsp_ready <= 1'b1;
    endtask

    // Wait for the matching response
    task automatic response(
            output [DATA_WIDTH-1:0]     dat,
            output                      err);
        rsp_s r;
        while (!rsp_ready || !rsp_valid) begin
            @(posedge clock);
        end
        r = rsp_dat;
        dat = r.dat;
        err = r.err;
        rsp_ready <= 1'b0;
    endtask

endinterface
