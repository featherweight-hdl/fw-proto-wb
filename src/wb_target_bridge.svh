// Target bridge -- the CONSUMER side. Extends fw_port #(wb_target_if) and runs an
// active loop: pop a captured request from the transactor-interface (vif.recv_req),
// hand it to the connected model (api.access -> rsp), then push the response back
// for the slave core to drive (vif.send_rsp). Connect this port to the component
// that implements wb_target_if (e.g. a memory model). Single outstanding by
// construction -- one request is serviced fully before the next is popped.
class wb_target_bridge #(type REQ = wb_types_pkg::wb_req_t,
                         type RSP = wb_types_pkg::wb_rsp_t)
        extends fw_port #(wb_target_if #(REQ, RSP));
    virtual wb_target_xtor_if vif;

    function new(string name, fw_component parent,
                 virtual wb_target_xtor_if vif);
        super.new(name, parent);
        this.vif = vif;
    endfunction

    task run();
        wb_target_if #(REQ, RSP) api = get_if();
        forever begin
            automatic REQ req;
            automatic RSP rsp;
            vif.recv_req(req);     // blocking: next captured request
            api.access(rsp, req);  // model produces the response (may block)
            vif.send_rsp(rsp);     // hand it to the slave core to drive on the bus
        end
    endtask
endclass
