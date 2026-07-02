// ----------------------------------------------------------------------------
// Wishbone Target transactor interface (SV, signal-level RV ports)
//
// Thin, FIFO-less bridge from the blocking task API (HVL side) to the core's
// ready/valid request/response channels -- the mirror of wb_initiator_xtor_if:
//   - wait_req() : SINK   -- drive req_ready, await a request beat, capture it
//   - send_rsp() : SOURCE -- drive rsp_dat/rsp_valid, await the core to accept
//
// Single outstanding by construction (one blocking task pair in flight). Task
// ports use the per-instance ADDR_WIDTH/DATA_WIDTH.
// ----------------------------------------------------------------------------

`include "wb_xtor_macros.svh"

interface wb_target_xtor_if #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int REQ_WIDTH  = (ADDR_WIDTH + DATA_WIDTH + (DATA_WIDTH/8) + 1),
        parameter int RSP_WIDTH  = (DATA_WIDTH + 1),
        parameter int DEPTH      = 4
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // RV request channel: core sources, interface accepts
        input  wire [REQ_WIDTH-1:0]     req_dat,
        input  wire                     req_valid,
        output reg                      req_ready,

        // RV response channel: interface sources, core accepts
        output reg [RSP_WIDTH-1:0]      rsp_dat,
        output reg                      rsp_valid,
        input  wire                     rsp_ready
    );

    typedef `WB_TARGET_REQ_S(ADDR_WIDTH, DATA_WIDTH) req_s;
    typedef `WB_TARGET_RSP_S(ADDR_WIDTH, DATA_WIDTH) rsp_s;

    // Wait for the next observed Wishbone request (SINK side of the req channel).
    // Unlike the initiator's response() -- which relies on request() having
    // pre-armed its ready -- wait_req() runs BEFORE send_rsp(), so it arms
    // req_ready itself.
    task automatic wait_req(
            output [ADDR_WIDTH-1:0]     adr,
            output [DATA_WIDTH-1:0]     dat,
            output [(DATA_WIDTH/8)-1:0] sel,
            output                      we);
        req_s r;
        req_ready <= 1'b1;
        while (!req_ready || !req_valid) begin
            @(posedge clock);
        end
        r   = req_dat;
        adr = r.adr;
        dat = r.dat;
        sel = r.sel;
        we  = r.we;
        req_ready <= 1'b0;
    endtask

    // Provide the response for the outstanding request (SOURCE side of the rsp
    // channel) -- mirror of the initiator's request().
    task automatic send_rsp(
            input [DATA_WIDTH-1:0]      dat,
            input                       err);
        rsp_s r;
        rsp_valid <= 1'b1;
        r = '{dat: dat, err: err};
        rsp_dat = r;

        do begin
            @(posedge clock);
        end while (!rsp_valid || !rsp_ready);
        rsp_valid <= 1'b0;
    endtask

    // Kept for API compatibility with the UVM/example consumers.
    task wait_reset();
        if (reset) @(negedge reset);
        @(posedge clock);
    endtask

endinterface
