// ----------------------------------------------------------------------------
// wb_proto_checker -- protocol-invariant checker for classic single-outstanding
// Wishbone (ACK/ERR). Passive: every port is an input, so it can be instantiated
// (or bound) on any WB bus -- in a formal harness, a sim testbench, or alongside
// real RTL. Protocol invariants belong WITH the protocol, so this ships in the kit.
//
// Two parallel layers checking the same B3 rules (see docs/protocol-property-
// checking.md for the methodology behind what is checked and why):
//   * SYNTHESIZABLE immediate-assert checkers -- single-edge `always @(posedge
//     clock)` with manually-registered history (no $past), so SymbiYosys/yosys
//     read them directly and they also run in any simulator. Always on.
//   * Concurrent SVA properties, gated by `ifdef WB_PROTO_SVA` -- richer, more
//     readable sim checking (incl. X-checks); excluded from the yosys/formal flow.
//
// SAFETY rules (Wishbone B3):
//   3.20        CYC/STB are negated the cycle after reset
//   3.25        CYC is asserted whenever STB qualifies a phase (envelope)
//   3.35/3.50   a termination is asserted only while CYC && STB
//   3.45        ACK and ERR are mutually exclusive
//   3.60        master holds the STB-qualified signals stable until terminated
//   (design)    classic is single-outstanding: at most one bus phase in flight
//   3.65        read data is valid (not X) at a read termination          [sim]
// BOUNDED LIVENESS (safety form):
//   forward progress -- every qualified phase terminates within MAX_WAIT cycles.
//   Enabled by CHECK_LIVENESS; disable for a slave that may legitimately stall
//   longer, or raise MAX_WAIT. In a free-environment formal proof this needs a
//   peer-fairness ASSUME (see tests/formal/wb_proto_fv.sv).
//
// NOTE on dependency direction: Wishbone INTENDS the slave's termination to depend
// on STB (RULE 3.35: ACK/ERR are generated *in response to* CYC && STB). This is
// the OPPOSITE of the AXI VALID/READY rule (VALID must not depend on READY) -- do
// not port the AXI independence assertion here.
// ----------------------------------------------------------------------------
module wb_proto_checker #(
        parameter int ADDR_WIDTH    = 32,
        parameter int DATA_WIDTH    = 32,
        parameter int MAX_WAIT      = 16,   // max cycles a phase may stay unterminated
        parameter bit CHECK_LIVENESS = 1'b1 // enable the bounded forward-progress check
    ) (
        input  wire                     clock,
        input  wire                     reset,
        input  wire [ADDR_WIDTH-1:0]    adr,
        input  wire [DATA_WIDTH-1:0]    dat_w,
        input  wire [DATA_WIDTH-1:0]    dat_r,
        input  wire [DATA_WIDTH/8-1:0]  sel,
        input  wire                     we,
        input  wire                     cyc,
        input  wire                     stb,
        input  wire                     ack,
        input  wire                     err
    );

    wire term      = ack || err;
    wire qualified = cyc && stb;          // an active, STB-qualified bus phase

    // ------------------------------------------------------------------------
    // Registered history (one-cycle delay), so the immediate-assert checkers are
    // self-contained and synthesizable (no $past).
    // ------------------------------------------------------------------------
    reg                     past_valid;
    reg                     reset_q;
    reg [ADDR_WIDTH-1:0]    adr_q;
    reg [DATA_WIDTH-1:0]    dat_w_q;
    reg [DATA_WIDTH/8-1:0]  sel_q;
    reg                     we_q, cyc_q, stb_q, term_q;

    initial past_valid = 1'b0;

    always @(posedge clock) begin
        past_valid <= 1'b1;
        reset_q    <= reset;
        adr_q      <= adr;
        dat_w_q    <= dat_w;
        sel_q      <= sel;
        we_q       <= we;
        cyc_q      <= cyc;
        stb_q      <= stb;
        term_q     <= term;
    end

    // Outstanding-phase count (rising-edge start, terminated end).
    reg [1:0] outst;
    wire ph_start = qualified && !(cyc_q && stb_q);   // active phase just began
    wire ph_term  = qualified && term;                // active phase terminating
    always @(posedge clock) begin
        if (reset)                          outst <= 2'd0;
        else if (ph_start && !ph_term)      outst <= outst + 2'd1;
        else if (ph_term  && !ph_start)     outst <= outst - 2'd1;
    end

    // Forward-progress wait counter: cycles the current phase has been active AND
    // unterminated. Cleared when idle or on termination.
    localparam int WCW = (MAX_WAIT < 2) ? 2 : ($clog2(MAX_WAIT + 2));
    reg [WCW-1:0] wait_cnt;
    always @(posedge clock) begin
        if (reset || !qualified || term) wait_cnt <= '0;
        else                             wait_cnt <= wait_cnt + 1'b1;
    end

    // ------------------------------------------------------------------------
    // Synthesizable immediate-assert checkers (yosys/SymbiYosys + simulator).
    // ------------------------------------------------------------------------
    always @(posedge clock) begin
        // 3.60: while a phase is in progress and unterminated, the master holds
        //       CYC/STB and the qualified request signals stable.
        if (!reset && past_valid && !reset_q) begin
            if ((cyc_q && stb_q) && !term_q) begin
                assert (qualified);
                assert (adr   == adr_q);
                assert (dat_w == dat_w_q);
                assert (sel   == sel_q);
                assert (we    == we_q);
            end
            // 3.35/3.50: a termination only rises while CYC && STB.
            if (term && !term_q)
                assert (qualified);
        end

        // 3.25: CYC envelope -- CYC is asserted whenever STB qualifies a phase.
        if (!reset && stb)
            assert (cyc);

        // 3.45: ACK and ERR never assert together.
        if (!reset)
            assert (!(ack && err));

        // 3.20: CYC/STB negated the cycle after reset.
        if (past_valid && reset_q)
            assert (!cyc && !stb);

        // single-outstanding: never more than one bus phase in flight.
        if (!reset)
            assert (outst <= 2'd1);

        // bounded forward progress: a qualified phase terminates within MAX_WAIT.
        if (!reset && CHECK_LIVENESS)
            assert (wait_cnt <= WCW'(MAX_WAIT));
    end

    // ------------------------------------------------------------------------
    // Non-vacuity covers -- prove the interesting cases are reachable, so a green
    // proof (or sim run) is not vacuously green.
    // ------------------------------------------------------------------------
    always @(posedge clock) begin
        if (!reset) begin
            cover (ph_start);                 // a phase starts
            cover (qualified && ack);         // a phase terminates with ACK
            cover (qualified && err);         // a phase terminates with ERR
        end
    end

`ifdef WB_PROTO_SVA
    // ------------------------------------------------------------------------
    // Concurrent SVA properties (simulation) -- the same rules, more readable,
    // plus value-domain (X) checks that have no meaning in the formal flow.
    // ------------------------------------------------------------------------
    default clocking cb @(posedge clock); endclocking
    default disable iff (reset);

    // 3.60 -- stable while unterminated.
    a_hold_cyc:   assert property ((qualified && !term) |=> qualified);
    a_hold_adr:   assert property ((qualified && !term) |=> (adr   == $past(adr)));
    a_hold_dat_w: assert property ((qualified && !term) |=> (dat_w == $past(dat_w)));
    a_hold_sel:   assert property ((qualified && !term) |=> (sel   == $past(sel)));
    a_hold_we:    assert property ((qualified && !term) |=> (we    == $past(we)));

    // 3.25 -- CYC envelope.
    a_cyc_env:    assert property (stb |-> cyc);

    // 3.45 -- mutual exclusion.
    a_mutex:      assert property (!(ack && err));

    // 3.35/3.50 -- framing.
    a_framing:    assert property ($rose(term) |-> qualified);

    // single-outstanding.
    a_single:     assert property (outst <= 2'd1);

    // bounded forward progress (SVA form): once qualified, term within MAX_WAIT.
    a_progress:   assert property (!CHECK_LIVENESS or (qualified |-> ##[0:MAX_WAIT] term));

    // 3.20 -- reset negation (don't disable on reset for this one).
    a_reset_neg:  assert property (@(posedge clock) $past(reset) |-> (!cyc && !stb));

    // value-domain (X) checks -- qualified controls/data are never unknown, and
    // read data is known at a read termination (RULE 3.65). Sim-only.
    a_no_x_req:   assert property (qualified |-> !$isunknown({adr, dat_w, sel, we}));
    a_no_x_rdat:  assert property ((qualified && ack && !we) |-> !$isunknown(dat_r));
`endif

endmodule
