# Overview

## What this kit is

`fw-proto-wb` is a **protocol kit**: a self-contained bundle of SystemVerilog
that connects a class-level transaction API to a signal-level bus — here, the
**Wishbone B3** classic bus (single, block, and read-modify-write cycles).

It follows the `fw-proto-kit` recipe, which decomposes a protocol into
**independent activity streams** and gives each stream the same six elements per
role. The intent is for the kit to be *isomorphic* to the ready/valid reference
kit it is modeled on — "ready/valid, plus a request/response phase and a richer
core FSM."

## Wishbone, reduced to one stream

Wishbone **classic** is **one** command stream with **two coupled phases**:

- a **request** phase the master issues (`ADR_O`, `DAT_O`, `SEL_O`, `WE_O`,
  `CYC_O`, `STB_O`), and
- a **response** phase the slave returns (`DAT_I`, `ACK_I`/`ERR_I`/`RTY_I`).

A classic master holds the request asserted until the slave terminates the *same*
phase, and there is exactly **one outstanding transfer** on the wire at a time
(classic Wishbone is non-pipelined). That collapses cleanly:

> **Wishbone classic = one stream = one task (`xfer(rsp, req)`) = one request
> FIFO + one response FIFO per role = one core FSM that drives a cycle and
> collects the termination.**

The FIFOs still buy **caller-side pipelining**: a driver can queue several
requests ahead of the bus while the core grinds them out one cycle at a time, in
order.

## Design principles

The kit rests on a handful of load-bearing rules inherited from `fw-proto-kit`:

Synchronous, queue-free cores
: Every core FSM is clocked and contains no SV queues or classes, so it is
  **synthesizable** — which is exactly what makes the back-to-back formal proof
  possible. Queues and class handles live only in the (non-synthesizable)
  transactor-interface layer.

Plain ready/valid internal links
: Every interface↔core link is a plain, clocked `valid`/`data`/`ready`
  handshake and *never* speaks Wishbone. A data-carrying role needs **two** such
  links (request and response). Wishbone lives only on the core's outward pins.

`ACK` is implicit
: Every `xfer`/`access` *completes* on a termination event. The response only
  needs to flag the abnormal terminations (`err`, `rty`); a normal completion is
  `ack = !err && !rty`. Two bits encode three mutually-exclusive outcomes plus
  "still running."

Outputs-first parameter order
: APIs read "rsp = xfer(req)" — the output (`rsp`) leads, the input (`req`)
  follows. This is the `fw-api-kit` convention and is consistent across every
  method and adapter.

Policy lives in the class layer
: The cores stay minimal. Block/RMW cycles, RTY-retry, ERR-escalation, and
  protocol-independence are all **adapters** in the class layer — testable,
  swappable, and out of the synthesizable core.

## The protocol-independence win

The biggest payoff is the `std_mem_if` adapter pair:

- **`wb_to_std`** layers a protocol-independent `read`/`write` API over a
  Wishbone initiator (retrying `RTY`, escalating `ERR`).
- **`std_to_wb`** backs a Wishbone slave with any `std_mem_if` memory model.

Code written against `std_mem_if` does not change when the underlying protocol is
swapped. See {doc}`adapters`.

## Scope and limits (first cut)

- **Fixed 32-bit widths.** `wb_types_pkg` fixes `WB_AW=32, WB_DW=32, WB_SW=4`.
  The class layer is width-agnostic; widening is a one-place change but is not
  per-instance configurable (see the design's open issue O-1).
- **Classic cycles only.** Registered-feedback bursts (`CTI`/`BTE`) are
  *designed-for but deferred* — additive to this architecture (O-2).
- **Registered (clocked) slave.** The slave core is intentionally clocked, so it
  always inserts at least one wait state; it cannot model a true zero-wait-state
  asynchronous slave (O-5).
- **In-order completion assumed.** The initiator pairs one request push with one
  response pop, relying on the bus completing transfers in issue order — true for
  classic Wishbone (O-7).

For the full list, see the {doc}`design reference <wb_proto_kit_design>`.
