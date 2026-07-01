// Wishbone protocol kit -- class layer. The transactor SV interfaces and modules
// (wb_*_xtor*.sv) are separate compilation units (an interface/module cannot live
// in a package); they are listed alongside this file in the FileSet.
//
// The APIs are individual-argument and width-parameterized (#(ADDR_WIDTH,
// DATA_WIDTH)). wb_proto_if is the single transfer API shared by both roles: the
// initiator bridge IMPLEMENTS it; a target model IMPLEMENTS it and the target bridge
// HOLDS it. The monitor bridge HOLDS a wb_monitor_if handle and drives it from a
// run() loop forked by start().
//
// The protocol-independent memory API (fw_mem_if) now lives in fw-hdl's
// fw_std_pkg; the Wishbone<->fw_mem_if adapters (wb_mem_initiator / wb_mem_target,
// below) bring it back here. Compiling this package therefore depends on fw-hdl
// (fw_hdl_pkg + fw_std_pkg); the core transactor bridges above stay fw-hdl-free.
`include "fw_std_macros.svh"                  // FW_MEM_IMP (from fw-hdl std)

package fw_proto_wb_pkg;
    import fw_hdl_pkg::*;                      // fw_component / fw_port / fw_export
    import fw_std_pkg::*;                      // fw_mem_if
    export fw_std_pkg::*;                      // re-export fw_mem_if to consumers

    // API interface-classes.
    `include "wb_proto_if.svh"           // shared initiator/target transfer API
    `include "wb_monitor_if.svh"

    // Transactor bridges -- hold a virtual transactor-interface and implement (or
    // drive) the API. They reference the transactor SV interfaces by their
    // (unmangled) names, so those interfaces must be compiled in the same image.
    `include "wb_initiator_xtor_bridge.svh"
    `include "wb_target_xtor_bridge.svh"
    `include "wb_monitor_xtor_bridge.svh"

    // Protocol-independent memory-access adapters (fw_mem_if <-> wb_proto_if).
    `include "wb_mem_adapters.svh"

endpackage
