# Bus data types

The protocol payload is a pair of **packed structs** defined in `wb_types_pkg`.
They are packed so the cores can carry them across the internal ready/valid links
as plain vectors, keeping the cores synthesizable (no SV queues or classes in
cores).

The first cut fixes the widths: `WB_AW=32`, `WB_DW=32`, `WB_SW=4` (32-bit port,
byte granularity). Tags (`TGA`/`TGC`/`TGD`) are *omitted while disabled* — a
0-width packed member is illegal SystemVerilog, so tags become real struct fields
only in a tagged variant; `WB_TW` is reserved.

## `wb_req_t` — the request phase

```systemverilog
typedef struct packed {
    logic [WB_AW-1:0] adr;       // address
    logic [WB_DW-1:0] dat;       // WRITE data (don't-care on reads)
    logic [WB_SW-1:0] sel;       // byte/granule selects (qualified by STB)
    logic             we;        // 1 = write, 0 = read
    logic             cyc_hold;  // keep CYC_O asserted after this beat's ACK
                                 //   (block / RMW chaining). 0 => classic single
                                 //   cycle (CYC drops with STB).
} wb_req_t;
```

## `wb_rsp_t` — the response phase

```systemverilog
typedef struct packed {
    logic [WB_DW-1:0] dat;       // READ data (valid only at termination)
    logic             err;       // ERR_I termination
    logic             rty;       // RTY_I termination
} wb_rsp_t;                       // ACK is implicit: completed xfer with !err && !rty
```

```{admonition} ACK is implicit
:class: note
Every `xfer()`/`access()` *completes* on a termination event
(`ACK | ERR | RTY`). The response only needs to distinguish the *abnormal*
terminations; a normal completion is `ack = !err && !rty`. The three terminations
are mutually exclusive (Wishbone RULE 3.45), so two bits encode three outcomes
plus "still running" (not yet returned).
```

## `wb_xfer_t` — the monitor record

A completed phase is the request and its response, sampled together at the
termination edge:

```systemverilog
typedef struct packed {
    wb_req_t req;
    wb_rsp_t rsp;
} wb_xfer_t;
```

## Width policy

The transactor (SV) layer uses the `wb_types_pkg` localparams directly, giving
clean un-mangled virtual handles. The class layer (APIs, bridges, adapters) is
parameterized `#(type REQ, type RSP)` and width-agnostic. To widen the port,
change `WB_AW`/`WB_DW`/`WB_SW` and the struct definitions in `wb_types_pkg` — one
place — and rebuild. Running a 32-bit and a 64-bit initiator in the *same* image
requires full symmetric parameterization of the SV files and is deferred (design
open issue O-1).
