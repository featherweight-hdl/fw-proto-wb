`include "wb_xtor_macros.svh"

// ----------------------------------------------------------------------------
// Wishbone Target (slave) core transactor (pure module, signal-level ports)
//
//   - Observes the classic Wishbone target signals
//   - Converts each single-cycle access to an RV request (req_)
//   - Waits for the RV response (rsp_), then drives ACK/ERR back on the bus
//   - Single outstanding transaction (no pipelining)
//
//   req_* : RV initiator port (core -> FIFO)  { adr, dat, we, sel(byte-en) }
//   rsp_* : RV target port    (FIFO -> core)  { dat, err }
//
// Migrated from fwvip-wb (authoritative transactor API). ack/err only.
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

        // RV request channel (core drives, FIFO accepts)
        output wire [REQ_WIDTH-1:0]     req_dat,
        output wire                     req_valid,
        input  wire                     req_ready,

        // RV response channel (FIFO drives, core accepts)
        input  wire [RSP_WIDTH-1:0]     rsp_dat,
        input  wire                     rsp_valid,
        output wire                     rsp_ready
    );

    typedef `WB_TARGET_REQ_S(ADDR_WIDTH, DATA_WIDTH) req_s;
    typedef `WB_TARGET_RSP_S(ADDR_WIDTH, DATA_WIDTH) rsp_s;

    // Latched Wishbone request fields
    reg [ADDR_WIDTH-1:0]     adr_q;
    reg [DATA_WIDTH-1:0]     dat_w_q;
    reg [(DATA_WIDTH/8)-1:0] sel_q;
    reg                      we_q;

    // Response latches
    reg [DATA_WIDTH-1:0]     dat_r_q;
    reg                      err_q;

    // Wishbone termination outputs (registered)
    reg                      ack_r;
    reg                      err_r;

    // RV request handshake
    reg                      req_valid_r;
    wire                     req_fire = req_valid && req_ready;

    // Pack request vector from latched fields
    req_s req_u;
    always_comb begin
        req_u.adr = adr_q;
        req_u.dat = dat_w_q;
        req_u.we  = we_q;
        req_u.sel = sel_q;
    end
    assign req_dat   = req_u;
    assign req_valid = req_valid_r;

    // Unpack response vector
    rsp_s rsp_u;
    always_comb begin
        rsp_u = rsp_s'(rsp_dat);
    end

    assign dat_r = dat_r_q;
    assign ack   = ack_r;
    assign err   = err_r;

    // Wishbone cycle is active when CYC & STB asserted
    wire active_cycle = cyc & stb;

    // FSM
    typedef enum logic [1:0] {
        IDLE     = 2'b00,
        REQ      = 2'b01,
        WAIT_RSP = 2'b10,
        RESP     = 2'b11
    } state_e;

    state_e state, state_n;

    // Accept a response beat only while actually awaiting one (WAIT_RSP): a proper
    // ready/valid handshake, so a beat that asserts ready+valid is genuinely
    // consumed (never dropped). In normal FIFO-fed use rsp_valid only asserts in
    // WAIT_RSP, so this is behaviour-neutral there; it also makes the back-to-back
    // formal proof's response accounting exact.
    assign rsp_ready = (state == WAIT_RSP);

    wire rsp_fire = (state == WAIT_RSP) && rsp_valid && rsp_ready;

    // Next-state
    always_comb begin
        state_n = state;
        case (state)
            IDLE: begin
                if (active_cycle) begin
                    state_n = REQ;
                end
            end
            REQ: begin
                if (!active_cycle) begin
                    state_n = IDLE;       // master aborted early
                end else if (req_fire) begin
                    state_n = WAIT_RSP;
                end
            end
            WAIT_RSP: begin
                if (!active_cycle) begin
                    state_n = IDLE;       // master aborted cycle
                end else if (rsp_fire) begin
                    state_n = RESP;
                end
            end
            RESP: begin
                // Hold the response until the master ENDS the phase (negates STB).
                // Returning to IDLE while CYC/STB are still asserted would let the
                // slave re-capture the very same phase as a spurious second request
                // (the master needs a cycle to react to ACK). Waiting for
                // !active_cycle is the proper WB slave handshake (cf. the prior
                // core's WB_ACK state).
                if (!active_cycle) begin
                    state_n = IDLE;
                end
            end
            default: state_n = IDLE;
        endcase
    end

    // Sequential logic
    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state       <= IDLE;
            adr_q       <= '0;
            dat_w_q     <= '0;
            sel_q       <= '0;
            we_q        <= 1'b0;
            dat_r_q     <= '0;
            err_q       <= 1'b0;
            req_valid_r <= 1'b0;
            ack_r       <= 1'b0;
            err_r       <= 1'b0;
        end else begin
            state <= state_n;

            // One-cycle ACK/ERR pulse while in RESP
            ack_r <= 1'b0;
            err_r <= 1'b0;
            if (state == RESP) begin
                ack_r <= ~err_q;
                err_r <= err_q;
            end

            case (state)
                IDLE: begin
                    req_valid_r <= 1'b0;
                    if (active_cycle) begin
                        // Latch incoming bus request
                        adr_q       <= adr;
                        dat_w_q     <= dat_w;
                        sel_q       <= sel;
                        we_q        <= we;
                        req_valid_r <= 1'b1;
                    end
                end
                REQ: begin
                    if (!active_cycle) begin
                        req_valid_r <= 1'b0;
                    end else if (req_fire) begin
                        req_valid_r <= 1'b0;
                    end
                end
                WAIT_RSP: begin
                    if (active_cycle && rsp_fire) begin
                        dat_r_q <= rsp_u.dat;
                        err_q   <= rsp_u.err;
                    end
                end
                default: ;
            endcase
        end
    end

endmodule
