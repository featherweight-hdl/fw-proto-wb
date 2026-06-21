// Target core: a clocked Wishbone SLAVE FSM. It is the slave on the bus pins, a
// PRODUCER on the request link (captured requests up to the iface) and a CONSUMER
// on the response link (responses down from the iface). On a new phase
// (CYC_I && STB_I) it captures the request and presents it up; it asserts NO
// termination until the response arrives (RULE 3.35/3.50 -- ACK only in response
// to STB); then it drives DAT_O + exactly one of ACK/ERR/RTY (RULE 3.45) until the
// master ends the phase (STB_I negates). Always registered => at least one wait
// state (design O-5: a true async/zero-wait slave is intentionally out of scope).
module wb_target_xtor_core
    import wb_types_pkg::*;
(
    input            clock,
    input            reset,
    // request link (to xtor_if): ready/valid PRODUCER
    output wb_req_t  req_data,
    output bit       req_valid,
    input            req_ready,
    // response link (from xtor_if): ready/valid CONSUMER
    input  wb_rsp_t  rsp_data,
    input            rsp_valid,
    output bit       rsp_ready,
    // Wishbone SLAVE pins
    input  [WB_AW-1:0] adr_i,
    input  [WB_DW-1:0] dat_i,
    input  [WB_SW-1:0] sel_i,
    input              we_i,
    input              cyc_i,
    input              stb_i,
    output bit [WB_DW-1:0] dat_o,
    output bit             ack_o,
    output bit             err_o,
    output bit             rty_o
);
    typedef enum bit [1:0] {WB_WATCH, WB_REQ, WB_WAIT, WB_ACK} state_t;
    state_t st;

    always @(posedge clock) begin
        if (reset) begin
            st        <= WB_WATCH;
            req_valid <= 1'b0;
            req_data  <= '0;
            rsp_ready <= 1'b0;
            dat_o     <= '0;
            ack_o     <= 1'b0;
            err_o     <= 1'b0;
            rty_o     <= 1'b0;
        end else case (st)
            WB_WATCH:
                if (cyc_i && stb_i) begin           // new bus phase qualified
                    req_data.adr      <= adr_i;
                    req_data.dat      <= dat_i;
                    req_data.sel      <= sel_i;
                    req_data.we       <= we_i;
                    req_data.cyc_hold <= 1'b0;       // not observable at the slave
                    req_valid         <= 1'b1;
                    st                <= WB_REQ;
                end

            WB_REQ:
                if (req_valid && req_ready) begin    // request-link transfer
                    req_valid <= 1'b0;
                    rsp_ready <= 1'b1;               // ready to take the response
                    st        <= WB_WAIT;
                end

            WB_WAIT:
                if (rsp_valid && rsp_ready) begin    // response-link transfer
                    // Drive exactly one termination (RULE 3.45) defensively, with
                    // priority err > rty > ack, so the bus contract holds even if a
                    // model hands back a malformed response with err && rty set.
                    dat_o     <= rsp_data.dat;
                    err_o     <= rsp_data.err;
                    rty_o     <= rsp_data.rty && !rsp_data.err;
                    ack_o     <= !(rsp_data.err || rsp_data.rty);
                    rsp_ready <= 1'b0;
                    st        <= WB_ACK;
                end

            WB_ACK:
                if (!stb_i) begin                    // master ended the phase
                    ack_o <= 1'b0;
                    err_o <= 1'b0;
                    rty_o <= 1'b0;
                    st    <= WB_WATCH;
                end

            default: st <= WB_WATCH;
        endcase
    end
endmodule
