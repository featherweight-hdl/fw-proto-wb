// Target-side adapter: PROVIDES wb_target_if (so the wb_target_bridge's port
// connects to it) and services each captured Wishbone request by calling a model
// that implements the protocol-independent std_mem_if (held via a port). This is
// the mirror of wb_to_std: it lets a plain std memory model back a Wishbone slave
// without knowing anything about Wishbone (fw-proto-kit SKILL "Adapters").
//
// Wire: wb_target_bridge.connect(std_to_wb.tgt) ;  std_to_wb.mem -> <model>.std
class std_to_wb extends fw_component;
    typedef logic [31:0] addr_t;
    typedef logic [31:0] data_t;
    typedef logic [3:0]  strb_t;

    fw_port #(std_mem_if #(addr_t, data_t, strb_t)) mem;   // to the memory model
    `FW_WB_TARGET_IMP(wb_req_t, wb_rsp_t, std_to_wb, tgt); // provided WB target API

    function new(string name, fw_component parent);
        super.new(name, parent);
        mem = new("mem", this);
        tgt = new(this);
    endfunction

    virtual task tgt_access(output wb_rsp_t rsp, input wb_req_t req);
        std_mem_if #(addr_t, data_t, strb_t) m = mem.get_if();
        automatic bit    err;
        automatic data_t data;
        rsp = '{dat:32'h0, err:1'b0, rty:1'b0};
        if (req.we) begin
            m.write(err, req.adr, req.dat, req.sel);
            rsp.err = err;
        end else begin
            m.read(data, err, req.adr);
            rsp.dat = data;
            rsp.err = err;
        end
    endtask
endclass
