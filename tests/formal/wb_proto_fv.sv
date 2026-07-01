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
// Post-migration (Decision D2): classic single-outstanding WB, ACK/ERR only -- no
// RTY and no CYC-hold. The internal ready/valid links carry the cores' packed
// request/response vectors directly (the initiator and target use the same
// {adr,dat,we,sel} request layout and {dat,err} response layout), so the proof
// compares the raw vectors end to end -- no field extraction needed.
//
// Run:  dfm run wb.proto.fv
// ======================================================================
`include "fw_proto_wb_macros.svh"

module wb_proto_fv #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int REQ_WIDTH  = (ADDR_WIDTH + DATA_WIDTH + (DATA_WIDTH/8) + 1),
    parameter int RSP_WIDTH  = (DATA_WIDTH + 1)
) (
    input  wire                  clock,
    input  wire                  reset,
    // free REQUEST producer feeding the master's req-link
    input  wire [REQ_WIDTH-1:0]  src_req,
    input  wire                  src_req_valid,
    // free sink draining the master's rsp-link
    input  wire                  snk_rsp_ready,
    // free model draining the slave's req-link
    input  wire                  mdl_req_ready,
    // free RESPONSE model feeding the slave's rsp-link
    input  wire [RSP_WIDTH-1:0]  mdl_rsp,
    input  wire                  mdl_rsp_valid
);
    // ---- Wishbone bus between the two cores (two unidirectional data buses:
    // wb_dat_w = master->slave write data, wb_dat_r = slave->master read data).
    // Declared/connected from `WB_WIRES / `WB_CONNECT (fw_proto_wb_macros.svh);
    // empty port-prefix because the cores expose bare WB pin names. ----
    `WB_WIRES(wb_, ADDR_WIDTH, DATA_WIDTH)

    // ---- internal ready/valid links ----
    wire                  i_req_ready;   // master req-link ready (to src)
    wire [RSP_WIDTH-1:0]  i_rsp_data;    // master rsp-link  (to sink)
    wire                  i_rsp_valid;
    wire [REQ_WIDTH-1:0]  t_req_data;    // slave  req-link  (to model)
    wire                  t_req_valid;
    wire                  t_rsp_ready;   // slave  rsp-link ready (to model)

    // initiator core: req-link CONSUMER (from src), rsp-link PRODUCER (to sink),
    // bus MASTER.
    wb_initiator_xtor_core #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) u_init (
        .clock(clock), .reset(reset),
        .req_dat(src_req), .req_valid(src_req_valid), .req_ready(i_req_ready),
        .rsp_dat(i_rsp_data), .rsp_valid(i_rsp_valid), .rsp_ready(snk_rsp_ready),
        `WB_CONNECT(, wb_)
    );

    // target core: bus SLAVE, req-link PRODUCER (to model), rsp-link CONSUMER
    // (from model).
    wb_target_xtor_core #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) u_targ (
        .clock(clock), .reset(reset),
        .req_dat(t_req_data), .req_valid(t_req_valid), .req_ready(mdl_req_ready),
        .rsp_dat(mdl_rsp), .rsp_valid(mdl_rsp_valid), .rsp_ready(t_rsp_ready),
        `WB_CONNECT(, wb_)
    );

    // The BUS-PROTOCOL invariants (stability while unterminated, ACK/ERR mutual
    // exclusion, termination framing, reset negation, single-outstanding) are
    // checked by the kit's reusable protocol checker -- always on, so its
    // immediate asserts become proof obligations here. This harness only adds the
    // properties the checker can't see: the internal ready/valid LINK contracts and
    // the end-to-end DATA-INTEGRITY round trip.
    wb_proto_checker #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
    ) u_chk (
        .clock(clock), .reset(reset),
        `WB_CONNECT(, wb_)
    );

`ifdef FORMAL
    // ---- preamble: mask first cycle, start in reset, then run ----
    // reset is a clean one-shot: asserted in the first cycle, deasserted and held
    // low thereafter. The back-to-back data-integrity proof is a steady-state
    // property; arbitrary mid-stream reset toggling is out of its scope (the reset
    // *behaviour* itself -- CYC/STB negation -- is checked by the protocol checker).
    reg f_past_valid = 1'b0;
    always @(posedge clock) f_past_valid <= 1'b1;
    always @(*) if (!f_past_valid) assume (reset);
    always @(posedge clock) if (f_past_valid) assume (!reset);

    // handshake events along the two paths
    wire in_req  = src_req_valid && i_req_ready;   // request enters master
    wire out_req = t_req_valid   && mdl_req_ready;  // request leaves slave
    wire in_rsp  = mdl_rsp_valid && t_rsp_ready;    // response enters slave
    wire out_rsp = i_rsp_valid   && snk_rsp_ready;  // response leaves master

    // BOUNDED PEER FAIRNESS -- so the bus makes forward progress (the protocol
    // checker's bounded-liveness assert). The free slave-side model must not stall
    // the request drain or the response provision for more than MODEL_MAX cycles.
    // This keeps the handshake/backpressure exploration (the link contracts below)
    // intact while guaranteeing eventual termination, well within the checker's
    // MAX_WAIT budget. Without this, a free model could stall forever and the
    // (legitimate) slave wait-states would have no bound to satisfy.
    localparam int MODEL_MAX = 2;
    reg [2:0] req_stall, rsp_stall;
    always @(posedge clock) begin
        if (reset)                              req_stall <= '0;
        else if (t_req_valid && !mdl_req_ready) req_stall <= req_stall + 1'b1;
        else                                    req_stall <= '0;
    end
    always @(posedge clock) begin
        if (reset)                              rsp_stall <= '0;
        else if (t_rsp_ready && !mdl_rsp_valid) rsp_stall <= rsp_stall + 1'b1;
        else                                    rsp_stall <= '0;
    end
    always @(*) begin
        assume (req_stall <= MODEL_MAX);
        assume (rsp_stall <= MODEL_MAX);
    end

    // LINK CONTRACTS -- a ready/valid producer holds valid+data stable while its
    // consumer stalls (master rsp-link, slave req-link). Internal links, so not
    // visible to the bus-level protocol checker.
    always @(posedge clock)
        if (!reset && f_past_valid && !$past(reset)) begin
            if ($past(i_rsp_valid) && !$past(snk_rsp_ready)) begin
                assert (i_rsp_valid);
                assert (i_rsp_data == $past(i_rsp_data));
            end
            if ($past(t_req_valid) && !$past(mdl_req_ready)) begin
                assert (t_req_valid);
                assert (t_req_data == $past(t_req_data));
            end
        end

    // DATA INTEGRITY end to end, via an arbitrary tracked position. Two
    //     trackers: the REQUEST path (master->slave) and the RESPONSE path
    //     (slave->master). One symbolic index proves all positions. The initiator
    //     and target use the same packed request layout and the same packed
    //     response layout, so the raw link vectors are compared directly.
    localparam int CW = 5;
    (* anyconst *) reg [CW-1:0] f_idx;

    reg [CW-1:0]            inq_cnt, outq_cnt, inr_cnt, outr_cnt;
    reg [REQ_WIDTH-1:0]    f_req;
    reg [RSP_WIDTH-1:0]    f_rsp;
    reg                    f_req_have, f_rsp_have;

    always @(posedge clock)
        if (reset) begin
            inq_cnt <= '0; outq_cnt <= '0; inr_cnt <= '0; outr_cnt <= '0;
            f_req_have <= 1'b0; f_rsp_have <= 1'b0;
        end else begin
            if (in_req) begin
                if (inq_cnt == f_idx) begin f_req <= src_req; f_req_have <= 1'b1; end
                inq_cnt <= inq_cnt + 1'b1;
            end
            if (out_req) outq_cnt <= outq_cnt + 1'b1;
            if (in_rsp) begin
                if (inr_cnt == f_idx) begin f_rsp <= mdl_rsp; f_rsp_have <= 1'b1; end
                inr_cnt <= inr_cnt + 1'b1;
            end
            if (out_rsp) outr_cnt <= outr_cnt + 1'b1;
        end

    // the f_idx-th request leaving the slave equals the f_idx-th that entered
    always @(posedge clock)
        if (!reset)
            if (out_req && (outq_cnt == f_idx)) begin
                assert (f_req_have);
                assert (t_req_data == f_req);
            end
    // the f_idx-th response leaving the master equals the f_idx-th model response
    always @(posedge clock)
        if (!reset)
            if (out_rsp && (outr_cnt == f_idx)) begin
                assert (f_rsp_have);
                assert (i_rsp_data == f_rsp);
            end

    // non-vacuity: a tracked request and response actually traverse end to end
    always @(posedge clock) begin
        cover (!reset && out_req && (outq_cnt == f_idx) && f_req_have);
        cover (!reset && out_rsp && (outr_cnt == f_idx) && f_rsp_have);
    end
`endif
endmodule
