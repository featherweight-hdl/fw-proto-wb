// Target (slave) API: service one captured Wishbone request and return the
// response the slave should drive back. The target bridge (a port) calls
// access(); the connected model implements it (via `FW_WB_TARGET_IMP). Outputs
// lead -- read "rsp = access(req)".
//   REQ : request beat type  (default wb_req_t)
//   RSP : response beat type (default wb_rsp_t)
interface class wb_target_if #(type REQ = wb_types_pkg::wb_req_t,
                               type RSP = wb_types_pkg::wb_rsp_t);
    // Given the request the master issued, produce the response to drive back.
    // May block (e.g. a slow memory model) -- the bus simply sees wait states.
    pure virtual task access(output RSP rsp, input REQ req);
endclass
