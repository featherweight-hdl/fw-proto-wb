// ======================================================================
// REQUIRED back-to-back SIMULATION test for the Wishbone kit (design §8a).
//
// Wires a full INITIATOR transactor directly to a full TARGET transactor over one
// shared Wishbone bus, with a MONITOR passively tapping it -- exercising the
// COMPLETE stack (class API -> bridge -> xtor_if FIFOs -> core -> pins and back),
// which the cores-only formal proof cannot reach. Acceptance criteria (§8a):
//   6.2a round-trip integrity   -- every read returns the prior write
//   6.2b backpressure both sides -- slave wait-states + master throttle
//   6.2c ERR + RTY               -- terminations propagate to the xfer() caller
//   6.2d block + RMW             -- cyc_hold chains (data round-trips; CYC-hold
//                                   invariant itself is proven in formal row 8)
//   6.2e monitor equality        -- observed phase count == completed transfers
//   6.2f watchdog                -- $fatal on hang; clean exit prints PASS
//
// Run:  dfm run wb.proto.tests.wb-proto      (expect: [wb_proto] PASS)
// ======================================================================
module wb_proto_tb;
    import fw_hdl_pkg::*;
    import wb_types_pkg::*;
    import wb_proto_pkg::*;

    // Special addresses the slave model treats specially.
    localparam logic [31:0] ERR_ADR = 32'hE000_0000;  // always ERR
    localparam logic [31:0] RTY_ADR = 32'h4000_0000;  // RTY twice, then ACK

    // --------------------------------------------------------------
    // Driver: consumes the initiator API; runs the full stimulus sequence and
    // checks round-trip integrity inline. Counts errors + completed transfers.
    // --------------------------------------------------------------
    class driver extends fw_component;
        fw_port #(wb_initiator_if #(wb_req_t, wb_rsp_t)) out;
        int unsigned errors;
        int unsigned n_xfers;          // completed transfers (for monitor check)

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        function void build();
            out = new("out", this);
        endfunction

        // One write transfer (cyc_hold chains a block/RMW).
        task automatic wr(input logic [31:0] adr, input logic [31:0] dat,
                          input bit hold = 1'b0);
            wb_initiator_if #(wb_req_t, wb_rsp_t) api = out.get_if();
            automatic wb_req_t req = '{adr:adr, dat:dat, sel:4'hf, we:1'b1,
                                       cyc_hold:hold};
            automatic wb_rsp_t rsp;
            api.xfer(rsp, req);
            n_xfers++;
            if (rsp.err || rsp.rty) begin
                $display("FAIL: write @0x%08h unexpectedly err=%0b rty=%0b",
                         adr, rsp.err, rsp.rty);
                errors++;
            end
        endtask

        // One read transfer; returns data via ref, flags err/rty out.
        task automatic rd(input logic [31:0] adr, output logic [31:0] dat,
                          output bit err, output bit rty, input bit hold = 1'b0);
            wb_initiator_if #(wb_req_t, wb_rsp_t) api = out.get_if();
            automatic wb_req_t req = '{adr:adr, dat:32'h0, sel:4'hf, we:1'b0,
                                       cyc_hold:hold};
            automatic wb_rsp_t rsp;
            api.xfer(rsp, req);
            n_xfers++;
            dat = rsp.dat; err = rsp.err; rty = rsp.rty;
        endtask

        // Read-and-check helper.
        task automatic rd_chk(input logic [31:0] adr, input logic [31:0] exp);
            automatic logic [31:0] got; automatic bit e, r;
            rd(adr, got, e, r);
            if (e || r) begin
                $display("FAIL: read @0x%08h err=%0b rty=%0b", adr, e, r); errors++;
            end else if (got !== exp) begin
                $display("FAIL: read @0x%08h got 0x%08h exp 0x%08h", adr, got, exp);
                errors++;
            end else
                $display("[driver] read  @0x%08h = 0x%08h OK", adr, got);
        endtask

        virtual task run();
            errors = 0; n_xfers = 0;

            // --- 6.2a: single writes then read-back (with master throttle 6.2b)
            for (int i = 0; i < 4; i++) begin
                wr(32'h0000_0100 + 4*i, 32'hA000_0000 + i);
                #13ns;                         // master throttle (backpressure)
            end
            for (int i = 0; i < 4; i++)
                rd_chk(32'h0000_0100 + 4*i, 32'hA000_0000 + i);

            // --- 6.2d: BLOCK write (CYC held across 4 phases) then block read-back
            for (int i = 0; i < 4; i++)
                wr(32'h0000_0200 + 4*i, 32'hB000_0000 + i, (i != 3));  // hold 0..2
            for (int i = 0; i < 4; i++)
                rd_chk(32'h0000_0200 + 4*i, 32'hB000_0000 + i);

            // --- 6.2d: RMW -- read under held CYC, then write the incremented value
            begin
                automatic logic [31:0] got; automatic bit e, r;
                rd(32'h0000_0100, got, e, r, /*hold=*/1'b1);   // read, keep CYC
                wr(32'h0000_0100, got + 1, /*hold=*/1'b0);     // write back +1
                rd_chk(32'h0000_0100, 32'hA000_0001);          // A000_0000 + 1
            end

            // --- 6.2c: ERR termination propagates
            begin
                automatic logic [31:0] got; automatic bit e, r;
                rd(ERR_ADR, got, e, r);
                if (!e) begin $display("FAIL: expected ERR @0x%08h", ERR_ADR); errors++; end
                else $display("[driver] ERR  @0x%08h OK", ERR_ADR);
            end

            // --- 6.2c: RTY termination, then retry to completion
            begin
                automatic logic [31:0] got; automatic bit e, r;
                automatic int tries = 0;
                do begin
                    rd(RTY_ADR, got, e, r);
                    tries++;
                end while (r && tries < 8);
                if (r) begin $display("FAIL: RTY never cleared @0x%08h", RTY_ADR); errors++; end
                else $display("[driver] RTY cleared after %0d tries OK", tries);
            end
        endtask
    endclass

    // --------------------------------------------------------------
    // Slave memory model: PROVIDES wb_target_if. Associative-array memory with
    // configurable latency (slave wait-states -> backpressure) and ERR/RTY hooks.
    // --------------------------------------------------------------
    class mem_slave extends fw_component;
        logic [31:0] mem [logic [31:0]];
        int unsigned rty_seen;                 // RTY_ADR returns RTY twice

        `FW_WB_TARGET_IMP(wb_req_t, wb_rsp_t, mem_slave, in);

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        function void build();
            in = new(this);
            rty_seen = 0;
        endfunction

        virtual task in_access(output wb_rsp_t rsp, input wb_req_t req);
            rsp = '{dat:32'h0, err:1'b0, rty:1'b0};
            #11ns;                              // slave latency (wait states)
            if (req.adr == ERR_ADR) begin
                rsp.err = 1'b1;
            end else if (req.adr == RTY_ADR && rty_seen < 2) begin
                rsp.rty = 1'b1; rty_seen++;
            end else if (req.we) begin
                mem[req.adr] = req.dat;
            end else begin
                rsp.dat = mem.exists(req.adr) ? mem[req.adr] : 32'h0;
            end
        endtask
    endclass

    // --------------------------------------------------------------
    // Observer: PROVIDES wb_monitor_if. Records every completed phase the monitor
    // taps (non-blocking observe()).
    // --------------------------------------------------------------
    class observer extends fw_component;
        wb_xfer_t seen[$];

        `FW_WB_MONITOR_IMP(wb_xfer_t, observer, mon);

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        function void build();
            mon = new(this);
        endfunction

        virtual function void mon_observe(input wb_xfer_t x);
            seen.push_back(x);
        endfunction
    endclass

    // --------------------------------------------------------------
    // Top: instances driver + slave + observer, builds the three bridges over the
    // transactor interfaces, and connects each to its peer.
    // --------------------------------------------------------------
    class wb_top extends fw_component;
        driver    drv;
        mem_slave slv;
        observer  obs;
        wb_target_bridge  #(wb_req_t, wb_rsp_t) tbr;
        wb_monitor_bridge #(wb_xfer_t)          mbr;
        virtual wb_initiator_xtor_if vif_init;
        virtual wb_target_xtor_if    vif_targ;
        virtual wb_monitor_xtor_if   vif_mon;

        function new(string name, fw_component parent);
            super.new(name, parent);
        endfunction

        function void build();
            drv = new("drv", this);
            slv = new("slv", this);
            obs = new("obs", this);
            drv.build();
            slv.build();
            obs.build();
        endfunction

        function void connect();
            // Initiator transactor: the driver's port connects to its export.
            wb_initiator_bridge #(wb_req_t, wb_rsp_t) ibr =
                new("init_bridge", this, vif_init);
            drv.out.connect(ibr.exp);

            // Target transactor: a port that calls into the slave model's export.
            tbr = new("targ_bridge", this, vif_targ);
            tbr.connect(slv.in);

            // Monitor transactor: a port that publishes to the observer's export.
            mbr = new("mon_bridge", this, vif_mon);
            mbr.connect(obs.mon);
        endfunction
    endclass

    // --------------------------------------------------------------
    // Signal-level setup: the three transactor modules on one shared WB bus.
    // Wishbone has TWO unidirectional data buses: dat_m2s (master->slave write)
    // and dat_s2m (slave->master read).
    // --------------------------------------------------------------
    logic clock = 1'b0;
    logic reset = 1'b1;

    bit [31:0] adr;
    bit [31:0] dat_m2s;
    bit [31:0] dat_s2m;
    bit [3:0]  sel;
    bit        we, cyc, stb, ack, err, rty;

    always #5ns clock = ~clock;

    wb_initiator_xtor init_xtor (
        .clock(clock), .reset(reset),
        .adr_o(adr), .dat_o(dat_m2s), .sel_o(sel), .we_o(we),
        .cyc_o(cyc), .stb_o(stb),
        .dat_i(dat_s2m), .ack_i(ack), .err_i(err), .rty_i(rty)
    );
    wb_target_xtor targ_xtor (
        .clock(clock), .reset(reset),
        .adr_i(adr), .dat_i(dat_m2s), .sel_i(sel), .we_i(we),
        .cyc_i(cyc), .stb_i(stb),
        .dat_o(dat_s2m), .ack_o(ack), .err_o(err), .rty_o(rty)
    );
    wb_monitor_xtor mon_xtor (
        .clock(clock), .reset(reset),
        .adr(adr), .dat_w(dat_m2s), .dat_r(dat_s2m), .sel(sel), .we(we),
        .cyc(cyc), .stb(stb), .ack(ack), .err(err), .rty(rty)
    );

    // Always-on bus checker: CYC must not drop while a phase is unterminated
    // (a slice of formal invariant row 8, useful as a live sim guard).
    bit past_valid = 1'b0;
    always @(posedge clock) begin
        if (!reset && past_valid) begin
            if ($past(cyc) && $past(stb) && !$past(ack || err || rty))
                if (!cyc) begin
                    $display("FAIL: CYC dropped mid-phase @ %0t", $time);
                end
        end
        past_valid <= 1'b1;
    end

    initial begin
        automatic wb_top top;
        automatic int errors = 0;
        automatic int unsigned exp_xfers;

        reset = 1'b1;
        repeat (4) @(posedge clock);
        reset = 1'b0;
        @(posedge clock);

        top = new("top", null);
        top.vif_init = init_xtor.u_if;
        top.vif_targ = targ_xtor.u_if;
        top.vif_mon  = mon_xtor.u_if;
        top.build();
        top.connect();

        // Start the target + monitor sampling loops, then run the driver.
        fork
            top.tbr.run();
            top.mbr.run();
        join_none
        top.drv.run();

        // Drain: let the last observed phase propagate to the monitor FIFO.
        repeat (20) @(posedge clock);

        errors    = top.drv.errors;
        exp_xfers = top.drv.n_xfers;

        // 6.2e: the monitor must have observed exactly the completed phases.
        if (top.obs.seen.size() != exp_xfers) begin
            $display("FAIL: monitor saw %0d phases, expected %0d",
                     top.obs.seen.size(), exp_xfers);
            errors++;
        end else
            $display("[monitor] observed %0d phases OK", top.obs.seen.size());

        if (errors == 0)
            $display("[wb_proto] PASS");
        else
            $display("[wb_proto] FAIL (%0d errors)", errors);
        $finish;
    end

    // Watchdog (6.2f) so a broken handshake fails fast instead of hanging.
    initial begin
        #200us;
        $fatal(1, "[wb_proto] TIMEOUT");
    end
endmodule
