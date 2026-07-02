`include "wb_xtor_macros.svh"

// ----------------------------------------------------------------------------
// Wishbone Target (slave) core transactor (pure module, signal-level ports)
//
//   - Observes the classic Wishbone target signals
//   - Presents each observed access as a ready/valid request (req_)
//   - Awaits the ready/valid response (rsp_), then drives ACK/ERR back on the bus
//   - Single outstanding transaction (no pipelining)
//
//   req_* : RV initiator port (core -> interface) { adr, dat, we, sel(byte-en) }
//   rsp_* : RV target port    (interface -> core) { dat, err }
//
// Lean matched counterpart of wb_initiator_xtor_core: the initiator drives ACK
// termination for a single cycle (STB negates the cycle after it samples ACK),
// so this target likewise pulses ACK/ERR for exactly ONE cycle -- the cycle the
// response is handed over -- rather than holding it until end-of-phase. Holding
// ACK across the boundary would let the (combinational) initiator re-sample the
// same ACK as the NEXT transaction's response. Classic ACK/ERR WB (no RTY).
// ----------------------------------------------------------------------------
module wb_target_xtor_core #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32,
        parameter int REQ_WIDTH  = (ADDR_WIDTH + DATA_WIDTH + (DATA_WIDTH/8) + 1),
        parameter int RSP_WIDTH  = (DATA_WIDTH + 1)
    ) (
        input  wire                     clock,
        input  wire                     reset,

        // Wishbone target (protocol) signals
        input  wire [ADDR_WIDTH-1:0]    adr,
        input  wire [DATA_WIDTH-1:0]    dat_w,
        output wire [DATA_WIDTH-1:0]    dat_r,
        input  wire                     cyc,
        output wire                     err,
        input  wire [DATA_WIDTH/8-1:0]  sel,
        input  wire                     stb,
        output wire                     ack,
        input  wire                     we,

        // RV request channel (core drives, interface accepts)
        output wire [REQ_WIDTH-1:0]     req_dat,
        output wire                     req_valid,
        input  wire                     req_ready,

        // RV response channel (interface drives, core accepts)
        input  wire [RSP_WIDTH-1:0]     rsp_dat,
        input  wire                     rsp_valid,
        output wire                     rsp_ready
    );

    typedef `WB_TARGET_REQ_S(ADDR_WIDTH, DATA_WIDTH) req_s;
    typedef `WB_TARGET_RSP_S(ADDR_WIDTH, DATA_WIDTH) rsp_s;

    // Pack the observed bus request { adr, dat, we, sel } onto the RV link.
    // The master holds these stable for the whole phase, so a combinational
    // pass-through is stable while presented (mirror of the initiator packing
    // its response combinationally from the bus).
    req_s req_u;
    always_comb begin
        req_u.adr = adr;
        req_u.dat = dat_w;
        req_u.we  = we;
        req_u.sel = sel;
    end
    assign req_dat = req_u;

    // Unpack the response { dat, err } from the RV link.
    rsp_s rsp_u;
    always_comb begin
        rsp_u = rsp_s'(rsp_dat);
    end

    // A Wishbone phase is active while CYC and STB are both asserted.
    wire active_cycle = cyc & stb;

    // Lean 3-state FSM (mirror of the initiator, plus the slave-only DRAIN):
    //   WATCH : present the observed request on req_ and wait for it to be taken
    //   RESP  : await the response on rsp_; drive ACK/ERR for the single handover
    //           cycle (combinational -- mirrors the initiator's rsp_valid on ACK)
    //   DRAIN : response delivered; wait for the master to end the phase (STB
    //           negated) before re-arming, so the same phase is not re-captured
    //           as a spurious second request. ACK is already low here.
    typedef enum logic [1:0] { WATCH, RESP, DRAIN } state_e;
    state_e state;

    assign req_valid = (state == WATCH) && active_cycle;
    assign rsp_ready = (state == RESP);

    wire req_fire = req_valid && req_ready;
    wire rsp_fire = rsp_ready && rsp_valid;

    // ACK/ERR and read data are driven only during the RESP handover cycle, and
    // only when the response beat is actually present -- a one-cycle pulse.
    assign ack   = (state == RESP) && rsp_valid && !rsp_u.err;
    assign err   = (state == RESP) && rsp_valid &&  rsp_u.err;
    assign dat_r = rsp_u.dat;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state <= WATCH;
        end else begin
            case (state)
                WATCH:   if (req_fire)       state <= RESP;
                RESP:    if (rsp_fire)       state <= DRAIN;
                DRAIN:   if (!active_cycle)  state <= WATCH;
                default:                     state <= WATCH;
            endcase
        end
    end

endmodule
