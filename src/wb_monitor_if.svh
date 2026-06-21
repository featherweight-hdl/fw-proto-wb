// Monitor API: receive one completed Wishbone phase (request + its response) the
// passive monitor observed on the bus. observe() is a FUNCTION (non-blocking) --
// monitor APIs may not block. Implemented (via `FW_WB_MONITOR_IMP) by a
// subscriber; the monitor bridge's port calls it.
//   XFER : observed-phase type (default wb_xfer_t -- {req, rsp})
interface class wb_monitor_if #(type XFER = wb_types_pkg::wb_xfer_t);
    // Publish one observed completed phase to the subscriber.
    pure virtual function void observe(input XFER xfer);
endclass
