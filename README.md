# fw-proto-wb — Wishbone B3 protocol kit

A Featherweight-HDL **protocol kit** that bridges a class-level API to the
signal-level **Wishbone B3** bus. Built on the `fw-proto-kit` pattern (six
elements per role) and modeled on the proven ready/valid reference kit.

- **Using the library (consumer guide):** [`skills/fw-proto-wb/SKILL.md`](skills/fw-proto-wb/SKILL.md)
  — how to import the package via `$IVPM_PACKAGES`, instance the transactors, and use the APIs.
- **Design:** [`docs/wb_proto_kit_design.md`](docs/wb_proto_kit_design.md)
- **Plan / progress:** [`docs/wb_proto_kit_plan.md`](docs/wb_proto_kit_plan.md)
- **Formal properties:** [`tests/formal/PROPERTIES.md`](tests/formal/PROPERTIES.md)

## What's in the kit

Three roles, each a full transactor (API class + IMP macro + bridge +
transactor-interface + clocked core + wrapper module):

| Role | API | Drives | Provided by |
| --- | --- | --- | --- |
| **initiator** (master) | `wb_initiator_if` — `xfer(rsp, req)` | CYC/STB/ADR/DAT_O/WE/SEL | `wb_initiator_bridge` |
| **target** (slave) | `wb_target_if` — `access(rsp, req)` | ACK/ERR/RTY/DAT_O | `wb_target_bridge` (port) |
| **monitor** | `wb_monitor_if` — `observe(xfer)` | — (taps only) | `wb_monitor_bridge` (port) |

Bus payloads are packed structs in `wb_types_pkg` (`wb_req_t`, `wb_rsp_t`,
`wb_xfer_t`). ACK is implicit (a completed `xfer` with `!err && !rty`); `cyc_hold`
chains block/RMW cycles. **Parameter order is outputs-first** (`xfer(rsp, req)`).

**Class-layer adapters** (the protocol-independence win):
- `wb_to_std` — provides the protocol-independent `std_mem_if`
  (`read`/`write`) over a Wishbone initiator; retries RTY, escalates ERR.
- `std_to_wb` — backs a Wishbone slave with any `std_mem_if` memory model.

## Build & run

The kit builds with dv-flow + Verilator; the formal proof additionally needs
sv2v + yosys + SymbiYosys. Set the IVPM env, then:

```bash
export IVPM_PACKAGES=<…>/fw-wb-dma/packages
export PATH=$IVPM_PACKAGES/python/bin:$IVPM_PACKAGES/verilator/bin:$IVPM_PACKAGES/yosys/bin:$PATH

dfm run wb.proto.wb-proto   # back-to-back sim (REQUIRED §8a)  -> [wb_proto] PASS
dfm run wb.proto.wb-std     # std -> WB -> std adapter stack   -> [wb_std]   PASS
dfm run wb.proto.fv        # back-to-back formal proof        -> DONE (PASS)
```

### Formal toolchain note
The bundled yosys (0.9) cannot read SV structs/packages, so the formal flow runs
the cores + harness through **`sv2v --exclude=Assert -DFORMAL`** first (see
`tests/formal/flow.yaml`). `--exclude=Assert` is mandatory — without it sv2v
strips every assertion and the proof passes vacuously. Re-run the teeth check in
`PROPERTIES.md` whenever a core changes.

## Widths (fixed 32-bit, first cut)

`wb_types_pkg` fixes `WB_AW=32, WB_DW=32, WB_SW=4` (32-bit port, byte
granularity). The class layer (APIs, bridges, adapters) is width-agnostic; the SV
transactor layer uses these localparams directly (clean, un-mangled `virtual`
handles — see design rule 5). Widening is a one-place change in `wb_types_pkg`;
per-instance multi-width support needs full symmetric parameterization (design
O-1, deferred).

## Minimal usage

A driver issuing Wishbone transfers, and a model servicing them:

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
        api.xfer(rsp, req);                 // outputs-first: rsp = xfer(req)
    endtask
endclass

// --- provider: implement the target API via the macro ---
class model extends fw_component;
    `FW_WB_TARGET_IMP(wb_req_t, wb_rsp_t, model, in);
    function void build(); in = new(this); endfunction
    task in_access(output wb_rsp_t rsp, input wb_req_t req);
        rsp = '{dat:32'h0, err:1'b0, rty:1'b0};
        /* service req … */
    endtask
endclass
```

Wire the bridges over the transactor modules' `u_if` and connect ports to exports
(see `tests/wb_proto_tb.sv` for the full pattern). For protocol-independent code,
drop in `wb_to_std` / `std_to_wb` and talk `std_mem_if` instead.

## Layout

```
src/   wb_types_pkg.sv  wb_proto_pkg.sv  wb_proto_macros.svh
       wb_{initiator,target,monitor}_if.svh / _bridge.svh / _xtor_if.sv / _xtor_core.sv / _xtor.sv
       std_mem_if.svh  wb_to_std.svh  std_to_wb.svh
tests/ wb_proto_tb.sv (back-to-back sim)   wb_std_tb.sv (adapter stack)
       formal/ wb_proto_fv.sv  PROPERTIES.md  flow.yaml
docs/  wb_proto_kit_design.md  wb_proto_kit_plan.md  wbspec_b3.md
```
