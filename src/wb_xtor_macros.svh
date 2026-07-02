
`ifndef INCLUDED_WB_XTOR_MACROS_SVH
`define INCLUDED_WB_XTOR_MACROS_SVH

// ----------------------------------------------------------------------
// Packed request/response struct templates for the signal-level WB
// transactor cores and interfaces. Each macro takes the per-instance
// ADDR_WIDTH / DATA_WIDTH so a single definition serves any bus width
// (classic single-outstanding WB: ack/err only -- no rty/cyc_hold).
//
// Migrated from the fwvip-wb VIP (the authoritative transactor API);
// the FWVIP_WB_* names were dropped in favor of the wb_* kit convention.
// ----------------------------------------------------------------------

`define WB_INITIATOR_REQ_S(ADDR_WIDTH, DATA_WIDTH) \
    struct packed { \
        bit[ADDR_WIDTH-1:0]     adr; \
        bit[DATA_WIDTH-1:0]     dat; \
        bit                     we;  \
        bit[(DATA_WIDTH/8)-1:0] sel; \
    }

`define WB_INITIATOR_RSP_S(ADDR_WIDTH, DATA_WIDTH) \
    struct packed { \
        bit[DATA_WIDTH-1:0]     dat; \
        bit                     err; \
    }

`define WB_TARGET_REQ_S(ADDR_WIDTH, DATA_WIDTH) \
    struct packed { \
        bit [ADDR_WIDTH-1:0]      adr; \
        bit [DATA_WIDTH-1:0]      dat; \
        bit                       we; \
        bit [(DATA_WIDTH/8)-1:0]  sel; \
    }

`define WB_TARGET_RSP_S(ADDR_WIDTH, DATA_WIDTH) \
    struct packed { \
        bit [DATA_WIDTH-1:0]      dat; \
        bit                       err; \
    }

`endif /* INCLUDED_WB_XTOR_MACROS_SVH */
