// ======================================================================
// Adapter test (design §7): a full PROTOCOL-INDEPENDENT stack
//
//   std_driver --std_mem_if--> [wb_to_std] --wb_initiator_if--> init xtor
//        == WB bus ==> target xtor --wb_target_if--> [std_to_wb]
//        --std_mem_if--> std_mem_model
//
// The driver and the memory model speak ONLY std_mem_if (read/write); Wishbone
// exists solely between the two adapters. Proves the "std API" win: user/model
// code is protocol-agnostic. Round-trips writes through the whole stack.
//
// Run:  dfm run wb.proto.tests.wb-std      (expect: [wb_std] PASS)
// ======================================================================
module wb_std_tb;
    import fw_pkg::*;
    import wb_types_pkg::*;
    import wb_proto_pkg::*;

    typedef logic [31:0] addr_t;
    typedef logic [31:0] data_t;
    typedef logic [3:0]  strb_t;

    // Driver: speaks only std_mem_if.
    class std_driver extends fw_component;
        fw_port #(std_mem_if #(addr_t, data_t, strb_t)) mem;
        int unsigned errors;

        function new(string name, fw_component parent); super.new(name, parent); endfunction
        function void build(); mem = new("mem", this); endfunction

        virtual task run();
            std_mem_if #(addr_t, data_t, strb_t) api = mem.get_if();
            automatic bit    err;
            automatic data_t got;
            errors = 0;
            for (int i = 0; i < 6; i++) begin
                api.write(err, 32'h0000_1000 + 4*i, 32'hD00D_0000 + i, 4'hf);
                if (err) begin $display("FAIL: write %0d err", i); errors++; end
            end
            for (int i = 0; i < 6; i++) begin
                api.read(got, err, 32'h0000_1000 + 4*i);
                if (err || got !== (32'hD00D_0000 + i)) begin
                    $display("FAIL: read %0d got 0x%08h err=%0b", i, got, err); errors++;
                end else
                    $display("[std_driver] @0x%08h = 0x%08h OK", 32'h0000_1000 + 4*i, got);
            end
        endtask
    endclass

    // Memory model: also speaks only std_mem_if.
    class std_mem_model extends fw_component;
        data_t mem [addr_t];
        `FW_STD_MEM_IMP(addr_t, data_t, strb_t, std_mem_model, m);

        function new(string name, fw_component parent); super.new(name, parent); endfunction
        function void build(); m = new(this); endfunction

        virtual task m_write(output bit err, input addr_t addr, input data_t data,
                             input strb_t strb);
            #7ns; mem[addr] = data; err = 1'b0;
        endtask
        virtual task m_read(output data_t data, output bit err, input addr_t addr);
            #7ns; data = mem.exists(addr) ? mem[addr] : 32'h0; err = 1'b0;
        endtask
    endclass

    // Top: builds the adapters + bridges and wires the std->WB->std stack.
    class std_top extends fw_component;
        std_driver     drv;
        std_mem_model  mdl;
        wb_to_std      w2s;
        std_to_wb      s2w;
        wb_target_bridge #(wb_req_t, wb_rsp_t) tbr;
        virtual wb_initiator_xtor_if vif_init;
        virtual wb_target_xtor_if    vif_targ;

        function new(string name, fw_component parent); super.new(name, parent); endfunction

        function void build();
            drv = new("drv", this);
            mdl = new("mdl", this);
            w2s = new("w2s", this);
            s2w = new("s2w", this);
            drv.build(); mdl.build();
        endfunction

        function void connect();
            // initiator side: driver -> wb_to_std -> initiator bridge export
            wb_initiator_bridge #(wb_req_t, wb_rsp_t) ibr =
                new("init_bridge", this, vif_init);
            drv.mem.connect(w2s.std);
            w2s.wb.connect(ibr.exp);
            // target side: target bridge -> std_to_wb -> memory model export
            tbr = new("targ_bridge", this, vif_targ);
            tbr.connect(s2w.tgt);
            s2w.mem.connect(mdl.m);
        endfunction
    endclass

    logic clock = 1'b0;
    logic reset = 1'b1;
    bit [31:0] adr, dat_m2s, dat_s2m;
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

    initial begin
        automatic std_top top;
        reset = 1'b1;
        repeat (4) @(posedge clock);
        reset = 1'b0;
        @(posedge clock);

        top = new("top", null);
        top.vif_init = init_xtor.u_if;
        top.vif_targ = targ_xtor.u_if;
        top.build();
        top.connect();

        fork top.tbr.run(); join_none
        top.drv.run();

        repeat (20) @(posedge clock);
        if (top.drv.errors == 0) $display("[wb_std] PASS");
        else                     $display("[wb_std] FAIL (%0d errors)", top.drv.errors);
        $finish;
    end

    initial begin
        #200us;
        $fatal(1, "[wb_std] TIMEOUT");
    end
endmodule
