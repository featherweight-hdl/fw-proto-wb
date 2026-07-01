// Monitor API: receive one completed Wishbone phase the passive monitor observed
// on the bus. Individual-argument + width-parameterized, mirroring the transactor's
// wait_txn(). observe() is a FUNCTION (non-blocking) -- monitor APIs may not block.
// Implemented by a subscriber; the monitor transactor bridge (wb_monitor_xtor_bridge)
// calls it for each observed phase.
//   adr/sel/we : the observed request qualifiers
//   dat        : the data word (write data on we=1, read data on we=0)
//   err        : ERR termination
interface class wb_monitor_if #(
        parameter int ADDR_WIDTH = 32,
        parameter int DATA_WIDTH = 32);

    // Publish one observed completed phase to the subscriber.
    pure virtual function void observe(
            input [ADDR_WIDTH-1:0]      adr,
            input [DATA_WIDTH-1:0]      dat,
            input [(DATA_WIDTH/8)-1:0]  sel,
            input                       we,
            input                       err);

endclass
