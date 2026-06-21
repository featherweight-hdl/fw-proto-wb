// Protocol-INDEPENDENT memory-access API. User/test logic and models written
// against std_mem_if do not change when the underlying protocol is swapped -- a
// per-protocol adapter (e.g. wb_to_std / std_to_wb) bridges it to the bus. This
// is the "std API" win described in the fw-proto-kit SKILL ("Adapters").
//
// Outputs lead (fw-api-kit "Parameter order"): read "data = read(addr)".
//   ADDR/DATA/STRB : address / data / byte-strobe types.
//   err            : escalated bus error (ERR termination, or RTY budget exhausted).
interface class std_mem_if #(type ADDR = logic [31:0],
                             type DATA = logic [31:0],
                             type STRB = logic [3:0]);
    // Write `data` (qualified by `strb`) to `addr`; err=1 on bus error.
    pure virtual task write(output bit err, input ADDR addr, input DATA data,
                            input STRB strb);
    // Read `addr` into `data`; err=1 on bus error.
    pure virtual task read(output DATA data, output bit err, input ADDR addr);
endclass
