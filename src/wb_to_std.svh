// Initiator-side adapter: PROVIDES the protocol-independent std_mem_if and drives
// it onto Wishbone through a port over wb_initiator_if. Pure class-layer logic --
// no new transactor, interface, or pins (fw-proto-kit SKILL "Adapters"). One
// std read/write becomes one Wishbone `xfer`; RTY is retried up to RTY_MAX, ERR
// (or exhausted retries) is escalated as the std `err` bit.
//
// Wire: <user>.port -> wb_to_std.std ;  wb_to_std.wb -> wb_initiator_bridge.exp
class wb_to_std extends fw_component;
    typedef logic [31:0] addr_t;
    typedef logic [31:0] data_t;
    typedef logic [3:0]  strb_t;

    localparam int unsigned RTY_MAX = 16;

    fw_port #(wb_initiator_if #(wb_req_t, wb_rsp_t)) wb;   // to the WB initiator
    `FW_STD_MEM_IMP(addr_t, data_t, strb_t, wb_to_std, std);  // provided std API

    function new(string name, fw_component parent);
        super.new(name, parent);
        wb  = new("wb", this);
        std = new(this);
    endfunction

    // One Wishbone transfer with RTY retry; returns the response.
    local task automatic do_xfer(output wb_rsp_t rsp, input wb_req_t req);
        wb_initiator_if #(wb_req_t, wb_rsp_t) api = wb.get_if();
        automatic int unsigned tries = 0;
        do begin
            api.xfer(rsp, req);
            tries++;
        end while (rsp.rty && tries < RTY_MAX);
    endtask

    virtual task std_write(output bit err, input addr_t addr, input data_t data,
                           input strb_t strb);
        automatic wb_req_t req = '{adr:addr, dat:data, sel:strb, we:1'b1,
                                   cyc_hold:1'b0};
        automatic wb_rsp_t rsp;
        do_xfer(rsp, req);
        err = rsp.err || rsp.rty;        // rty here => retry budget exhausted
    endtask

    virtual task std_read(output data_t data, output bit err, input addr_t addr);
        automatic wb_req_t req = '{adr:addr, dat:32'h0, sel:4'hf, we:1'b0,
                                   cyc_hold:1'b0};
        automatic wb_rsp_t rsp;
        do_xfer(rsp, req);
        data = rsp.dat;
        err  = rsp.err || rsp.rty;
    endtask
endclass
