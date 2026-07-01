# fw-proto-wb — Wishbone B3 Protocol Kit

A [Featherweight-HDL](https://github.com/featherweight-hdl) **protocol kit** that
bridges a class-level API to the signal-level **Wishbone B3** bus. It is built on
the `fw-proto-kit` pattern (six elements per role) and modeled on the proven
ready/valid reference kit.

The kit lets verification and modeling code speak a clean, blocking,
transaction-level API — `xfer(rsp, req)` on the initiator, `access(rsp, req)` on
the target — while the transactor layer drives and samples real Wishbone pins.
A pair of class-layer adapters (`wb_to_std` / `std_to_wb`) further lifts the API
to a **protocol-independent** `read`/`write` interface, so models written against
it survive a change of bus protocol.

```{admonition} Status
:class: tip
The kit is implemented and green: back-to-back simulation passes
(`[wb_proto] PASS` and `[wb_std] PASS`), and the back-to-back SymbiYosys formal
proof of the two cores passes (`DONE (PASS)`), non-vacuously and with a
bug-injection teeth check.
```

## The three roles

Three roles, each a full transactor (API class + IMP macro + bridge +
transactor-interface + clocked core + wrapper module):

| Role | API | Drives | Provided by |
| --- | --- | --- | --- |
| **initiator** (master) | `wb_initiator_if` — `xfer(rsp, req)` | CYC/STB/ADR/DAT_O/WE/SEL | `wb_initiator_bridge` |
| **target** (slave) | `wb_target_if` — `access(rsp, req)` | ACK/ERR/RTY/DAT_O | `wb_target_bridge` |
| **monitor** | `wb_monitor_if` — `observe(xfer)` | — (taps only) | `wb_monitor_bridge` |

## Where to start

- New here? Read the {doc}`overview` for the design philosophy, then
  {doc}`getting-started` to build and run the demonstrators.
- Writing code against the kit? See the {doc}`api-reference` and {doc}`adapters`.
- Curious how it stays synthesizable and provable? See {doc}`architecture` and
  {doc}`verification`.

```{toctree}
:maxdepth: 2
:caption: Guide

overview
getting-started
architecture
data-types
api-reference
adapters
verification
protocol-property-checking
```

```{toctree}
:maxdepth: 1
:caption: Design reference

wb_proto_kit_design
wb_proto_kit_plan
```
