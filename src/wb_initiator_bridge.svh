// Initiator bridge -- the PROVIDER side. Holds a virtual transactor-interface
// handle and implements wb_initiator_if via the API's `FW_WB_INITIATOR_IMP macro
// (never hand-rolled). xfer() redirects to exp_xfer(), which calls vif.xfer()
// (queue the request, block until the matching response returns). A consumer's
// port (e.g. the driver) connects to the export member `exp`.
class wb_initiator_bridge #(type REQ = wb_types_pkg::wb_req_t,
                            type RSP = wb_types_pkg::wb_rsp_t) extends fw_component;
    virtual wb_initiator_xtor_if vif;

    `FW_WB_INITIATOR_IMP(REQ, RSP, wb_initiator_bridge #(REQ, RSP), exp);

    function new(string name, fw_component parent,
                 virtual wb_initiator_xtor_if vif);
        super.new(name, parent);
        this.vif = vif;
        exp = new(this);
    endfunction

    virtual task exp_xfer(output RSP rsp, input REQ req);
        vif.xfer(rsp, req);
    endtask
endclass
