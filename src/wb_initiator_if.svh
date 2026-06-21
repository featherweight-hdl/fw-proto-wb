// Initiator (master) API: issue one Wishbone transfer and block until it
// terminates (ACK | ERR | RTY). Outputs lead -- read "rsp = xfer(req)" (fw-api-kit
// "Parameter order"). Implemented (via `FW_WB_INITIATOR_IMP) by the initiator
// bridge, whose export the driver's port connects to.
//   REQ : request beat type  (default wb_req_t -- adr/dat/sel/we/cyc_hold)
//   RSP : response beat type (default wb_rsp_t -- dat/err/rty; ack implicit)
interface class wb_initiator_if #(type REQ = wb_types_pkg::wb_req_t,
                                  type RSP = wb_types_pkg::wb_rsp_t);
    // Drive one transfer; blocks until the slave terminates it. rsp carries read
    // data + err/rty (ack == completed with !err && !rty).
    pure virtual task xfer(output RSP rsp, input REQ req);
endclass
