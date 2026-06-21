# Architecture

## The six elements per role

For each role the kit builds the same six things; the only deltas between roles
are how many internal links there are and how big the core FSM is. File names
follow the `wb_<role>_*` convention.

1. **API class** (`wb_<role>_if.svh`) — the pure-virtual interface class callers
   program against.
2. **IMP macro** (in `wb_proto_macros.svh`) — the implementation template every
   provider of that API must use.
3. **Transactor-interface** (`wb_<role>_xtor_if.sv`) — holds the FIFO(s), maps
   the blocking API methods onto the internal ready/valid link(s). Not
   synthesizable (it holds SV queues).
4. **Clocked core** (`wb_<role>_xtor_core.sv`) — the Wishbone master/slave FSM on
   the pins; a producer/consumer on the internal links. Synthesizable.
5. **Wrapper module** (`wb_<role>_xtor.sv`) — instances the interface + core,
   wires the internal links, and exposes CLK/RST + the Wishbone pins.
6. **Bridge** (`wb_<role>_bridge.svh`) — the class-layer object that connects the
   API port/export to the transactor's virtual interface handle.

## The internal link contract

Per `fw-proto-kit` design rules, **every interface↔core link is a plain, clocked
ready/valid handshake** (`up_valid`/`up_data`/`up_ready`) and never speaks
Wishbone. A data-carrying role needs **two** such links — one for the request
phase, one for the response phase:

```text
initiator:  xfer_if  --req link (rv)-->  [master core]  --WB bus-->  ...
            xfer_if  <--rsp link (rv)--  [master core]  <--WB bus--  ...

target:     ... --WB bus-->  [slave core]  --req link (rv)-->  xtor_if --recv_req--> bridge
            ... <--WB bus--  [slave core]  <--rsp link (rv)--  xtor_if <--send_rsp-- bridge
```

The `up_data` of the request link is the packed `wb_req_t`; of the response link,
the packed `wb_rsp_t`. Each link is a true one-beat-per-`(valid && ready)`
handshake (a registered passthrough would duplicate beats), and both endpoints
are clocked. Because the cores carry the payload as plain packed vectors and hold
no queues, they stay synthesizable — and therefore formally provable
back-to-back.

## Per-role data flow

### Initiator (master)

The transactor-interface holds a **request FIFO** and a **response FIFO**.
`xfer(rsp, req)` pushes the request (blocking only when full), then blocks
popping the matching response. Ordering across the pair is guaranteed because
classic Wishbone completes transfers in issue order.

The **master core**, per accepted request: asserts `CYC_O`/`STB_O`, drives
`ADR/DAT_O/WE/SEL`, holds them stable until it samples `ACK_I|ERR_I|RTY_I`,
captures `DAT_I` + flags into a response beat, pushes it on the response link,
and drops `STB_O` (and `CYC_O` unless `req.cyc_hold`).

### Target (slave) — the mirror

The transactor-interface's **request FIFO** is *filled* from the request link
(`recv_req` pops, blocks if empty) and its **response FIFO** is *drained* to the
response link (`send_rsp` pushes, blocks if full) — the initiator flipped.

The **slave core** watches `CYC_I && STB_I`; on a new phase it captures the
request and pushes it up, asserting **no termination yet**, then waits for the
response beat and drives `DAT_O` + exactly one of `ACK_O/ERR_O/RTY_O` until the
master drops `STB_I`.

The bridge's `run()` loop ties it together:
`recv_req(req)` → `access(rsp, req)` → `send_rsp(rsp)`.

```{admonition} Mutual-exclusion hardening
:class: note
The slave core enforces a defensive priority `err > rty > ack` so that a
malformed model response asserting both `err` and `rty` can never drive two
terminations at once (Wishbone RULE 3.45). This bug was found by the formal
proof.
```

### Monitor

The monitor core watches the bus; on each completed phase
(`CYC_I && STB_I && (ACK_I|ERR_I|RTY_I)`) it assembles a `wb_xfer_t` (request
*and* response sampled at the termination edge) and pushes it on a single
ready/valid link. It drives nothing. The bridge fans the records out via the
non-blocking `observe()` function.

```{admonition} Monitor cannot backpressure
:class: warning
The monitor taps the bus and cannot stall it. A shallow capture path can drop
beats at back-to-back bus rate — size the monitor FIFO generously (design open
issue O-6).
```

## Block, RMW, and CYC ownership

Classic single cycles drop `CYC_O` with `STB_O` every transfer. **Block** and
**RMW** cycles instead hold `CYC_O` asserted across several phases. Rather than
invent block/RMW core states, the design exposes **one extra request bit**,
`cyc_hold`: the master keeps `CYC_O` asserted after a beat's termination iff
`cyc_hold` is set, dropping only `STB_O` between phases.

- **Block transfer** = N requests with `cyc_hold=1` on the first N−1 and `=0` on
  the last.
- **RMW** = a read (`we=0`, `cyc_hold=1`) immediately followed by a write
  (`we=1`, `cyc_hold=0`) to the same address, under one held `CYC`.

This keeps the core minimal and pushes block/RMW *policy* into the class layer,
which is where the kit wants higher-level intent to live.

## Parameterization strategy

Wishbone has three natural widths (`AW`, `DW`, `SW`). The design rule is to
parameterize **symmetrically end-to-end, or not at all**, because a parameter
mangles the SV interface type and must then be threaded through every virtual
handle, bridge, and wrapper.

For the first cut the widths are fixed as localparams in `wb_types_pkg`
(`WB_AW=32, WB_DW=32, WB_SW=4`), giving clean, un-mangled `virtual
wb_<role>_xtor_if` handles and zero parameter-threading risk. The **class layer**
(APIs, bridges, adapters) stays parameterized `#(type REQ, type RSP)` and is
width-agnostic because it only ever moves the structs around. Widening is a
one-place change in the package; true per-instance multi-width is deferred (O-1).
