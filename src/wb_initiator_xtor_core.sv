`include "wb_xtor_macros.svh"

// ----------------------------------------------------------------------------
// Wishbone Initiator core transactor (pure module, signal-level ports)
//
// Bridges a ready/valid request/response stream (FIFO side) to the classic
// Wishbone initiator protocol (protocol side). Single outstanding request.
//   - req_* : RV target port  (FIFO -> core)   { adr, dat, we, stb(byte-en) }
//   - rsp_* : RV initiator port (core -> FIFO)  { dat, err }
//
// Migrated from fwvip-wb (authoritative transactor API). Classic single-
// outstanding WB: terminates on ACK or ERR (no RTY, no CYC-hold).
// ----------------------------------------------------------------------------
module wb_initiator_xtor_core #(
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
        output wire                     we,

        // RV request channel (FIFO drives, core accepts)
        input  wire [REQ_WIDTH-1:0]     req_dat,
        input  wire                     req_valid,
        output wire                     req_ready,

        // RV response channel (core drives, FIFO accepts)
        output wire [RSP_WIDTH-1:0]     rsp_dat,
        output wire                     rsp_valid,
        input  wire                     rsp_ready
    );

    typedef `WB_INITIATOR_REQ_S(ADDR_WIDTH, DATA_WIDTH) req_s;
    typedef `WB_INITIATOR_RSP_S(ADDR_WIDTH, DATA_WIDTH) rsp_s;

    // Unpack request vector into struct
    req_s req_u;
    always_comb begin
        req_u = req_s'(req_dat);
    end

    // Internal registers driving Wishbone outputs
    reg [ADDR_WIDTH-1:0]     adr_r;
    reg [DATA_WIDTH-1:0]     dat_w_r;
    reg [DATA_WIDTH/8-1:0]   sel_r;       // Byte enables (from req_u.stb)
    reg                      stb_r;       // Strobe
    reg                      cyc_r;       // Cycle indicator
    reg                      we_r;        // Write enable

    assign adr   = adr_r;
    assign dat_w = dat_w_r;
    assign sel   = sel_r;
    assign stb   = stb_r;
    assign cyc   = cyc_r;
    assign we    = we_r;

    // Response registers
    reg [DATA_WIDTH-1:0]     dat_r_q;
    reg                      err_q;
    reg                      rsp_valid_r;

    // Pack response { dat, err }
    rsp_s rsp_u;
    always_comb begin
        rsp_u.dat = dat_r_q;
        rsp_u.err = err_q;
    end
    assign rsp_dat   = rsp_u;
    assign rsp_valid = rsp_valid_r;

    // Accept a new request only while idle
    wire req_fire = req_valid && req_ready;
    wire rsp_fire = rsp_valid && rsp_ready;

    // Termination when ACK or ERR asserted
    wire term = ack || err;

    // State machine
    typedef enum logic [1:0] {
        IDLE = 2'b00,
        BUS  = 2'b01,
        RESP = 2'b10
    } state_e;

    state_e state;

    assign req_ready = (state == IDLE);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state        <= IDLE;
            adr_r        <= '0;
            dat_w_r      <= '0;
            sel_r        <= '0;
            stb_r        <= 1'b0;
            cyc_r        <= 1'b0;
            we_r         <= 1'b0;
            dat_r_q      <= '0;
            err_q        <= 1'b0;
            rsp_valid_r  <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    // Accept a new request
                    if (req_fire) begin
                        adr_r       <= req_u.adr;
                        dat_w_r     <= req_u.dat;
                        sel_r       <= req_u.stb;
                        we_r        <= req_u.we;
                        stb_r       <= 1'b1;
                        cyc_r       <= 1'b1;
                        state       <= BUS;
`ifdef DEBUG
                        $display("[INIT][%0t] IDLE->BUS adr=0x%08x dat=0x%08x we=%0b sel=%0h", $time, req_u.adr, req_u.dat, req_u.we, req_u.stb);
`endif
                    end
                end
                BUS: begin
                    // Wait for ACK or ERR termination (CYC/STB held until term)
                    if (term) begin
                        dat_r_q     <= dat_r;
                        err_q       <= err;
                        stb_r       <= 1'b0;
                        cyc_r       <= 1'b0;
                        rsp_valid_r <= 1'b1;
                        state       <= RESP;
`ifdef DEBUG
                        $display("[INIT][%0t] BUS->RESP term ack=%0b err=%0b dat_r=0x%08x", $time, ack, err, dat_r);
`endif
                    end
                end
                RESP: begin
                    // Hold response until consumed
                    if (rsp_fire) begin
                        rsp_valid_r <= 1'b0;
                        state       <= IDLE;
`ifdef DEBUG
                        $display("[INIT][%0t] RESP->IDLE rsp consumed", $time);
`endif
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end

endmodule
