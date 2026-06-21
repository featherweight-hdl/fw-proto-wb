// ======================================================================
// Back-to-back FORMAL verification component for the Wishbone kit (design §8).
//
// Wires the kit's two PROTOCOL CORES -- wb_initiator_xtor_core (master) and
// wb_target_xtor_core (slave) -- directly together over the Wishbone bus and lets
// SymbiYosys prove the connection. The cores are the kit's real, synthesizable
// RTL (clocked FSMs). Because Wishbone is request/response, the harness drives TWO
// free streams: a free REQUEST producer into the master's req-link (and a free
// model draining the slave's req-link), and a free RESPONSE model into the slave's
// rsp-link (drained back out of the master's rsp-link to a free sink):
//
//   free req src --req--> [master]==WB==>[slave] --req--> free model
//   free sink   <--rsp-- [master]<==WB==[slave] <--rsp-- free model
//
// All boundary signals are module inputs => free formal inputs, so the solver
// explores every legal interleaving and backpressure pattern. (yosys 0.9 cannot
// read SV structs/packages, so the flow runs this file + the cores through sv2v
// -DFORMAL into plain Verilog first; see tests/formal/flow.yaml.)
//
// Run:  dfm run wb.proto.formal.fv
// ======================================================================
module wb_proto_fv
    import wb_types_pkg::*;
(
    input  wire     clock,
    input  wire     reset,
    // free REQUEST producer feeding the master's req-link
    input  wb_req_t src_req,
    input  wire     src_req_valid,
    // free sink draining the master's rsp-link
    input  wire     snk_rsp_ready,
    // free model draining the slave's req-link
    input  wire     mdl_req_ready,
    // free RESPONSE model feeding the slave's rsp-link
    input  wb_rsp_t mdl_rsp,
    input  wire     mdl_rsp_valid
);
    // ---- Wishbone bus between the two cores (two unidirectional data buses) ----
    wire [WB_AW-1:0] adr;
    wire [WB_DW-1:0] dat_m2s;     // master -> slave (write data)
    wire [WB_DW-1:0] dat_s2m;     // slave -> master (read data)
    wire [WB_SW-1:0] sel;
    wire             we, cyc, stb, ack, err, rty;

    // ---- internal ready/valid links ----
    wire     i_req_ready;         // master req-link ready (to src)
    wb_rsp_t i_rsp_data;          // master rsp-link  (to sink)
    wire     i_rsp_valid;
    wb_req_t t_req_data;          // slave  req-link  (to model)
    wire     t_req_valid;
    wire     t_rsp_ready;         // slave  rsp-link ready (to model)

    // initiator core: req-link CONSUMER (from src), rsp-link PRODUCER (to sink),
    // bus MASTER.
    wb_initiator_xtor_core u_init (
        .clock(clock), .reset(reset),
        .req_data(src_req), .req_valid(src_req_valid), .req_ready(i_req_ready),
        .rsp_data(i_rsp_data), .rsp_valid(i_rsp_valid), .rsp_ready(snk_rsp_ready),
        .adr_o(adr), .dat_o(dat_m2s), .sel_o(sel), .we_o(we),
        .cyc_o(cyc), .stb_o(stb),
        .dat_i(dat_s2m), .ack_i(ack), .err_i(err), .rty_i(rty)
    );

    // target core: bus SLAVE, req-link PRODUCER (to model), rsp-link CONSUMER
    // (from model).
    wb_target_xtor_core u_targ (
        .clock(clock), .reset(reset),
        .req_data(t_req_data), .req_valid(t_req_valid), .req_ready(mdl_req_ready),
        .rsp_data(mdl_rsp), .rsp_valid(mdl_rsp_valid), .rsp_ready(t_rsp_ready),
        .adr_i(adr), .dat_i(dat_m2s), .sel_i(sel), .we_i(we),
        .cyc_i(cyc), .stb_i(stb),
        .dat_o(dat_s2m), .ack_o(ack), .err_o(err), .rty_o(rty)
    );

`ifdef FORMAL
    // ---- preamble: mask first cycle, start in reset ----
    reg f_past_valid = 1'b0;
    always @(posedge clock) f_past_valid <= 1'b1;
    always @(*) if (!f_past_valid) assume (reset);

    // Environment constraint: a well-behaved slave MODEL returns at most one
    // termination per response (err and rty are mutually exclusive). The slave
    // core still defends against a malformed response (priority err>rty>ack, so
    // mutual exclusion holds unconditionally); this assume scopes the end-to-end
    // RESPONSE-integrity proof to well-formed responses, whose mapping is defined.
    always @(*) assume (!(mdl_rsp.err && mdl_rsp.rty));

    wire term = ack || err || rty;

    // handshake events along the two paths
    wire in_req  = src_req_valid && i_req_ready;   // request enters master
    wire out_req = t_req_valid   && mdl_req_ready;  // request leaves slave
    wire in_rsp  = mdl_rsp_valid && t_rsp_ready;    // response enters slave
    wire out_rsp = i_rsp_valid   && snk_rsp_ready;  // response leaves master

    // (1) BUS CONTRACT -- master holds the STB-qualified signals stable while the
    //     phase is unterminated (RULE 3.60).
    always @(posedge clock)
        if (f_past_valid && !$past(reset))
            if ($past(cyc && stb) && !$past(term)) begin
                assert (cyc && stb);
                assert (adr     == $past(adr));
                assert (dat_m2s == $past(dat_m2s));
                assert (sel     == $past(sel));
                assert (we      == $past(we));
            end

    // (2) LINK CONTRACTS -- a ready/valid producer holds valid+data stable while
    //     its consumer stalls (master rsp-link, slave req-link).
    always @(posedge clock)
        if (f_past_valid && !$past(reset)) begin
            if ($past(i_rsp_valid) && !$past(snk_rsp_ready)) begin
                assert (i_rsp_valid);
                assert (i_rsp_data == $past(i_rsp_data));
            end
            if ($past(t_req_valid) && !$past(mdl_req_ready)) begin
                assert (t_req_valid);
                assert (t_req_data == $past(t_req_data));
            end
        end

    // (3) MUTUAL EXCLUSION -- at most one of ACK/ERR/RTY (RULE 3.45).
    always @(posedge clock)
        if (!reset)
            assert (!((ack && err) || (ack && rty) || (err && rty)));

    // (4) FRAMING -- a termination is only ASSERTED on a cycle where CYC&&STB
    //     (RULE 3.35/3.50). Rising-edge form (a registered slave deasserts ACK one
    //     cycle after STB drops, which is legal "in response to STB negation").
    always @(posedge clock)
        if (f_past_valid && !$past(reset))
            if (term && !$past(term))
                assert (cyc && stb);

    // (5) RESET -- CYC/STB negated the cycle after RST_I (RULE 3.20).
    always @(posedge clock)
        if (f_past_valid && $past(reset))
            assert (!cyc && !stb);

    // (6) RANGE -- classic is single-outstanding on the bus: never more than one
    //     bus phase in flight.
    reg [1:0] outst;
    reg       past_cycstb;                 // registered (cyc&&stb); $past not legal
    always @(posedge clock) past_cycstb <= (cyc && stb);
    wire ph_start = (cyc && stb) && !past_cycstb;   // rising edge of an active phase
    wire ph_term  = (cyc && stb) && term;
    always @(posedge clock)
        if (reset)
            outst <= 2'd0;
        else begin
            if (ph_start && !ph_term)      outst <= outst + 2'd1;
            else if (ph_term && !ph_start) outst <= outst - 2'd1;
        end
    always @(posedge clock)
        if (!reset) assert (outst <= 2'd1);

    // (7) DATA INTEGRITY end to end, via an arbitrary tracked position. Two
    //     trackers: the REQUEST path (master->slave) and the RESPONSE path
    //     (slave->master). One symbolic index proves all positions.
    localparam int CW = 5;
    (* anyconst *) reg [CW-1:0] f_idx;

    // request key = the bus-relevant fields (cyc_hold is not observable downstream)
    wire [WB_AW+WB_DW+WB_SW:0] in_req_key  =
        {src_req.adr,    src_req.dat,    src_req.sel,    src_req.we};
    wire [WB_AW+WB_DW+WB_SW:0] out_req_key =
        {t_req_data.adr, t_req_data.dat, t_req_data.sel, t_req_data.we};
    // response key = data + err/rty
    wire [WB_DW+1:0] in_rsp_key  = {mdl_rsp.dat,    mdl_rsp.err,    mdl_rsp.rty};
    wire [WB_DW+1:0] out_rsp_key = {i_rsp_data.dat, i_rsp_data.err, i_rsp_data.rty};

    reg [CW-1:0]            inq_cnt, outq_cnt, inr_cnt, outr_cnt;
    reg [WB_AW+WB_DW+WB_SW:0] f_req;
    reg [WB_DW+1:0]          f_rsp;
    reg                      f_req_have, f_rsp_have;

    always @(posedge clock)
        if (reset) begin
            inq_cnt <= '0; outq_cnt <= '0; inr_cnt <= '0; outr_cnt <= '0;
            f_req_have <= 1'b0; f_rsp_have <= 1'b0;
        end else begin
            if (in_req) begin
                if (inq_cnt == f_idx) begin f_req <= in_req_key; f_req_have <= 1'b1; end
                inq_cnt <= inq_cnt + 1'b1;
            end
            if (out_req) outq_cnt <= outq_cnt + 1'b1;
            if (in_rsp) begin
                if (inr_cnt == f_idx) begin f_rsp <= in_rsp_key; f_rsp_have <= 1'b1; end
                inr_cnt <= inr_cnt + 1'b1;
            end
            if (out_rsp) outr_cnt <= outr_cnt + 1'b1;
        end

    // the f_idx-th request leaving the slave equals the f_idx-th that entered
    always @(posedge clock)
        if (!reset)
            if (out_req && (outq_cnt == f_idx)) begin
                assert (f_req_have);
                assert (out_req_key == f_req);
            end
    // the f_idx-th response leaving the master equals the f_idx-th model response
    always @(posedge clock)
        if (!reset)
            if (out_rsp && (outr_cnt == f_idx)) begin
                assert (f_rsp_have);
                assert (out_rsp_key == f_rsp);
            end

    // non-vacuity: a tracked request and response actually traverse end to end
    always @(posedge clock) begin
        cover (!reset && out_req && (outq_cnt == f_idx) && f_req_have);
        cover (!reset && out_rsp && (outr_cnt == f_idx) && f_rsp_have);
    end
`endif
endmodule
