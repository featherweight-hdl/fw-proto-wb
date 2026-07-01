// Monitor transactor bridge -- the CONSUMER side (like the target). Holds a handle
// to the signal-level transactor interface (wb_monitor_xtor_if) AND a handle to the
// subscriber that implements the canonical wb_monitor_if API. start() forks the
// run() loop: BLOCK on the transactor's wait_txn() (one observed completed phase),
// then publish it via the NON-BLOCKING monitor API observe().
// Parameterized by the bus widths (ADDR_WIDTH/DATA_WIDTH).
//
// The transactor reports one data word per phase (write data on WE=1, read data on
// WE=0); it is forwarded as-is -- the subscriber interprets it by `we`.
class wb_monitor_xtor_bridge #(int unsigned ADDR_WIDTH = 32,
                               int unsigned DATA_WIDTH = 32);

    virtual wb_monitor_xtor_if #(ADDR_WIDTH, DATA_WIDTH) vif;
    wb_monitor_if #(ADDR_WIDTH, DATA_WIDTH)              monitor_if;   // subscriber

    function new(virtual wb_monitor_xtor_if #(ADDR_WIDTH, DATA_WIDTH) vif,
                 wb_monitor_if #(ADDR_WIDTH, DATA_WIDTH) monitor_if);
        this.vif        = vif;
        this.monitor_if = monitor_if;
    endfunction

    // Launch the observe loop as a background thread.
    task start();
        fork
            run();
        join_none
    endtask

    // Publish each observed completed phase to the subscriber (non-blocking).
    task run();
        forever begin
            automatic logic [ADDR_WIDTH-1:0]     adr;
            automatic logic [DATA_WIDTH-1:0]     dat;
            automatic logic [(DATA_WIDTH/8)-1:0] sel;
            automatic logic                      we;
            automatic logic                      err;
            vif.wait_txn(adr, dat, sel, we, err);     // blocking: next observed phase
            monitor_if.observe(adr, dat, sel, we, err); // non-blocking publish
        end
    endtask
endclass
