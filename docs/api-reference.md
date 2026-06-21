# API reference

The kit ships three interface classes — one per role — each with a companion
implementation macro in `wb_proto_macros.svh`. Every API ships a macro, and any
implementation of an API **must** use that macro to define the implementation
redirect rather than hand-rolling the `fw_export` proxy.

All methods follow the **outputs-first** convention: the return value leads,
the input follows — read "rsp = xfer(req)".

## Initiator API

Issue one Wishbone transfer and block until it terminates.

```systemverilog
interface class wb_initiator_if #(type REQ = wb_req_t, type RSP = wb_rsp_t);
    pure virtual task xfer(output RSP rsp, input REQ req);
endclass
```

Obtain the API from a port and drive a transfer:

```systemverilog
wb_initiator_if #(wb_req_t, wb_rsp_t) api = out.get_if();
wb_req_t req = '{adr:32'h100, dat:32'hcafe, sel:4'hf, we:1'b1, cyc_hold:1'b0};
wb_rsp_t rsp;
api.xfer(rsp, req);                 // outputs-first: rsp = xfer(req)
```

## Target API

The model side. The target bridge hands the slave model a captured request and
blocks for the response it should drive back.

```systemverilog
interface class wb_target_if #(type REQ = wb_req_t, type RSP = wb_rsp_t);
    pure virtual task access(output RSP rsp, input REQ req);
endclass
```

```{admonition} Symmetric directionality
:class: note
Unlike a one-way ready/valid kit (initiator `send`, target `put`), Wishbone is
request/response, so **both** the initiator and target APIs are
`(REQ in, RSP out)`. The difference is *who blocks on whom*: the initiator's
`xfer` blocks on the bus round-trip; the target's `access` is *called by* the
bridge and blocks the bridge until the model produces the response.
```

## Monitor API

Non-blocking — a function, never blocks — delivering one completed phase.

```systemverilog
interface class wb_monitor_if #(type XFER = wb_xfer_t);
    pure virtual function void observe(input XFER xfer);
endclass
```

## Implementation macros

Each macro emits the `fw_export` subclass and a member named `NAME`; an
implementation supplies a `NAME_<method>` task/function that the macro redirects
to. Each macro call needs a trailing `;`.

| Macro | Redirects | Method kind |
| --- | --- | --- |
| `` `FW_WB_INITIATOR_IMP(REQ, RSP, IMP, NAME) `` | `xfer(rsp, req)` → `NAME_xfer` | task (blocking) |
| `` `FW_WB_TARGET_IMP(REQ, RSP, IMP, NAME) `` | `access(rsp, req)` → `NAME_access` | task (blocking) |
| `` `FW_WB_MONITOR_IMP(XFER, IMP, NAME) `` | `observe(xfer)` → `NAME_observe` | function (non-blocking) |
| `` `FW_STD_MEM_IMP(ADDR, DATA, STRB, IMP, NAME) `` | `write(...)` → `NAME_write`, `read(...)` → `NAME_read` | tasks (blocking) |

Implement the target API via its macro:

```systemverilog
class model extends fw_component;
    `FW_WB_TARGET_IMP(wb_req_t, wb_rsp_t, model, in);
    function void build(); in = new(this); endfunction

    task in_access(output wb_rsp_t rsp, input wb_req_t req);
        rsp = '{dat:32'h0, err:1'b0, rty:1'b0};
        /* service req … */
    endtask
endclass
```

## Putting it together

A consumer holds a `fw_port` over the initiator API; a provider implements the
target API via the macro. Wire the bridges over the transactor modules' `u_if`
handles and connect ports to exports — see `tests/wb_proto_tb.sv` for the full
pattern.

```systemverilog
import fw_pkg::*; import wb_types_pkg::*; import wb_proto_pkg::*;

// --- consumer: hold a port over the initiator API ---
class driver extends fw_component;
    fw_port #(wb_initiator_if #(wb_req_t, wb_rsp_t)) out;
    function void build(); out = new("out", this); endfunction
    task run();
        wb_initiator_if #(wb_req_t, wb_rsp_t) api = out.get_if();
        wb_req_t req = '{adr:32'h100, dat:32'hcafe, sel:4'hf, we:1'b1, cyc_hold:1'b0};
        wb_rsp_t rsp;
        api.xfer(rsp, req);
    endtask
endclass
```

For protocol-independent code, drop in `wb_to_std` / `std_to_wb` and talk
`std_mem_if` instead — see {doc}`adapters`.
