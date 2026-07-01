// Initiator transactor bridge -- the PROVIDER side. Holds a handle to the
// signal-level transactor interface (wb_initiator_xtor_if) and IMPLEMENTS the
// canonical protocol API wb_proto_if directly. access() maps to the
// transactor's tasks: a request-FIFO push followed by a response-FIFO pop.
// Parameterized by the bus widths (ADDR_WIDTH/DATA_WIDTH).
class wb_initiator_xtor_bridge #(int unsigned ADDR_WIDTH = 32,
                                 int unsigned DATA_WIDTH = 32)
        implements wb_proto_if #(ADDR_WIDTH, DATA_WIDTH);

    virtual wb_initiator_xtor_if #(ADDR_WIDTH, DATA_WIDTH) vif;

    function new(virtual wb_initiator_xtor_if #(ADDR_WIDTH, DATA_WIDTH) vif);
        this.vif = vif;
    endfunction

    // Launch any required background threads. The initiator is call-driven
    // (access() does request-then-response inline), so there is nothing to start.
    task start();
    endtask

    // Implement the canonical API in terms of the transactor tasks: push the
    // request, then block for the matching response (classic single-outstanding).
    virtual task access(
            input  [ADDR_WIDTH-1:0]      adr,
            input  [DATA_WIDTH-1:0]      dat_w,
            input  [(DATA_WIDTH/8)-1:0]  sel,
            input                        we,
            output [DATA_WIDTH-1:0]      dat_r,
            output                       err);
        vif.request(adr, dat_w, sel, we);
        vif.response(dat_r, err);
    endtask
endclass
