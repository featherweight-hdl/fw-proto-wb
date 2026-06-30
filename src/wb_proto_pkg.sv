// Wishbone protocol kit -- class layer. The transactor SV interfaces and modules
// (wb_*_xtor*.sv) are separate compilation units (an interface/module cannot live
// in a package); they are listed alongside this file in the FileSet and share the
// bus types via wb_types_pkg.
//
// Macros are included BEFORE the package so they are visible where the bridges
// use them. fw_hdl_pkg supplies fw_component / fw_port / fw_export; wb_types_pkg
// supplies wb_req_t / wb_rsp_t / wb_xfer_t.
`include "wb_proto_macros.svh"

package wb_proto_pkg;
    import fw_hdl_pkg::*;
    import wb_types_pkg::*;
    // Re-export the bus types so code that imports only wb_proto_pkg sees them.
    export wb_types_pkg::*;

    // API interface-classes (each ships a `FW_WB_*_IMP macro, see wb_proto_macros).
    `include "wb_initiator_if.svh"
    `include "wb_target_if.svh"
    `include "wb_monitor_if.svh"
    `include "std_mem_if.svh"             // protocol-independent memory API

    // Bridge classes -- hold a virtual transactor-interface and implement/consume
    // the API. They reference the transactor SV interfaces by their (unmangled)
    // names, so those interfaces must be compiled in the same image.
    `include "wb_initiator_bridge.svh"
    `include "wb_target_bridge.svh"
    `include "wb_monitor_bridge.svh"

    // Class-layer adapters: map the protocol-independent std API to/from Wishbone.
    `include "wb_to_std.svh"              // initiator-side: provides std_mem_if
    `include "std_to_wb.svh"              // target-side: consumes std_mem_if

endpackage
