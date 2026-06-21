# Getting started

## Prerequisites

The kit builds with [dv-flow](https://dv-flow.github.io/) + Verilator. The formal
proof additionally needs `sv2v`, `yosys`, and SymbiYosys.

These tools are provisioned through the repo's IVPM package set. Point the
environment at the package directory and put the tool `bin` directories on
`PATH`:

```bash
export IVPM_PACKAGES=<…>/fw-wb-dma/packages
export PATH=$IVPM_PACKAGES/python/bin:$IVPM_PACKAGES/verilator/bin:$IVPM_PACKAGES/yosys/bin:$PATH
```

## Build & run

The kit ships two simulation gates and one formal gate, all driven by `dfm run`:

```bash
dfm run wb.proto.tests.wb-proto   # back-to-back sim (the REQUIRED §8a test)  -> [wb_proto] PASS
dfm run wb.proto.tests.wb-std     # std -> WB -> std adapter stack            -> [wb_std]   PASS
dfm run wb.proto.formal.fv        # back-to-back formal proof of the cores    -> DONE (PASS)
```

`wb.proto.tests.wb-proto`
: Wires a full **initiator transactor** directly to a full **target
  transactor** over one shared Wishbone bus (with a **monitor** tapping it) and
  proves data integrity end-to-end through the complete stack — write→read
  round-trip, backpressure on both sides, ERR + RTY terminations, and block/RMW
  chains. This is the primary acceptance test.

`wb.proto.tests.wb-std`
: Drives a full **std → Wishbone → std** stack, where the driver and the memory
  model speak only `std_mem_if` and the adapters bridge to the bus. Demonstrates
  the protocol-independence path.

`wb.proto.formal.fv`
: A SymbiYosys proof that wires the two synthesizable cores back-to-back and
  verifies the Wishbone normative rules plus end-to-end request/response
  integrity. See {doc}`verification`.

## Formal toolchain note

The bundled yosys (0.9) cannot read SystemVerilog structs/packages, so the formal
flow first runs the cores + harness through:

```bash
sv2v --exclude=Assert -DFORMAL …
```

```{warning}
`--exclude=Assert` is **mandatory**. Without it, sv2v silently strips every
assertion and the proof passes *vacuously* — a failure mode caught only by the
mandatory bug-injection teeth check. See `tests/formal/PROPERTIES.md` and re-run
the teeth check whenever a core changes.
```

## Repository layout

```text
src/   wb_types_pkg.sv  wb_proto_pkg.sv  wb_proto_macros.svh
       wb_{initiator,target,monitor}_if.svh / _bridge.svh
       wb_{initiator,target,monitor}_xtor_if.sv / _xtor_core.sv / _xtor.sv
       std_mem_if.svh  wb_to_std.svh  std_to_wb.svh
tests/ wb_proto_tb.sv (back-to-back sim)   wb_std_tb.sv (adapter stack)
       formal/ wb_proto_fv.sv  PROPERTIES.md  flow.yaml
docs/  Sphinx documentation (this site)
```

## Building this documentation

The docs are a standard Sphinx project under `docs/`:

```bash
cd docs
python -m pip install -r requirements.txt
make html          # output in docs/_build/html/index.html
```

The same build runs in CI and publishes to GitHub Pages on every push to `main`
— see the `.github/workflows/docs.yml` workflow.
