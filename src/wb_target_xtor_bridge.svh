// Target transactor bridge -- the CONSUMER side. Holds a handle to the signal-
// level transactor interface (wb_target_xtor_if) AND a handle to the model that
// implements the canonical wb_proto_if API. start() forks the run() service loop:
// for each captured request, wait for it, ask the model for the response, then
// drive the response back on the bus. Single outstanding by construction.
// Parameterized by the bus widths (ADDR_WIDTH/DATA_WIDTH).
class wb_target_xtor_bridge #(int unsigned ADDR_WIDTH = 32,
                              int unsigned DATA_WIDTH = 32);

    virtual wb_target_xtor_if #(ADDR_WIDTH, DATA_WIDTH) vif;
    wb_proto_if #(ADDR_WIDTH, DATA_WIDTH)              target_if;

    function new(virtual wb_target_xtor_if #(ADDR_WIDTH, DATA_WIDTH) vif,
                 wb_proto_if #(ADDR_WIDTH, DATA_WIDTH) target_if);
        this.vif       = vif;
        this.target_if = target_if;
    endfunction

    // Launch the service loop as a background thread.
    task start();
        fork
            run();
        join_none
    endtask

    // Service one captured request at a time: pop it from the transactor, ask the
    // model for the response, drive the response back on the bus.
    task run();
        forever begin
            automatic logic [ADDR_WIDTH-1:0]     adr;
            automatic logic [DATA_WIDTH-1:0]     dat_w;
            automatic logic [(DATA_WIDTH/8)-1:0] sel;
            automatic logic                      we;
            automatic logic [DATA_WIDTH-1:0]     dat_r;
            automatic logic                      err;
            vif.wait_req(adr, dat_w, sel, we);                 // next captured request
            target_if.access(adr, dat_w, sel, we, dat_r, err); // model -> response
            vif.send_rsp(dat_r, err);                          // drive it on the bus
        end
    endtask
endclass
