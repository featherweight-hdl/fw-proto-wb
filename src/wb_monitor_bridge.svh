// Monitor bridge -- a CONSUMER like the target. Extends fw_port #(wb_monitor_if)
// and runs an active loop: it BLOCKS on vif.get(x) (the transactor-interface's
// blocking method) and then fans the observed phase out via the NON-BLOCKING
// monitor API observe(). Connect this port to the subscriber that implements
// wb_monitor_if.
class wb_monitor_bridge #(type XFER = wb_types_pkg::wb_xfer_t)
        extends fw_port #(wb_monitor_if #(XFER));
    virtual wb_monitor_xtor_if vif;

    function new(string name, fw_component parent,
                 virtual wb_monitor_xtor_if vif);
        super.new(name, parent);
        this.vif = vif;
    endfunction

    task run();
        wb_monitor_if #(XFER) api = get_if();
        forever begin
            automatic XFER x;
            vif.get(x);            // blocking: next observed completed phase
            api.observe(x);        // non-blocking: publish to subscriber
        end
    endtask
endclass
