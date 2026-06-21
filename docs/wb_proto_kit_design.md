# Wishbone B3 Protocol Kit — Design (for review)

**Status:** design proposal, pre-implementation.
**Scope:** a Featherweight-HDL *protocol kit* (`fw-proto-wb`) that bridges a
class-level API to the signal-level **Wishbone B3** bus, modeled directly on the
proven ready/valid reference kit in
`fw-hdl/skills/fw-proto-kit/references/example/`.
**Sources reviewed:** `docs/wbspec_b3.md` (Wishbone B3, Sept 2002); the three
fw skills (`fw-api-kit`, `fw-proto-kit`, `fw-hdl`); the ready/valid reference
kit (every `src/` file, the demonstrator TB, and the back-to-back formal
harness).

The intent is to produce a kit that is *isomorphic* to the ready/valid kit — same
six elements per role, same internal-link discipline, same back-to-back formal
proof — so a reviewer who knows the rv kit can read this as "rv, plus a
request/response phase and a richer core FSM."

---

## 1. What Wishbone is, reduced to streams

Per `fw-proto-kit` SKILL ("Decomposing a protocol into streams"), the first job
is to count the **independent activity streams** (each its own handshake +
backpressure + FIFO + core-FSM segment).

Wishbone **classic** (single, block, RMW) is **one** command stream with **two
phases**:

- a **request** phase the master issues (`ADR_O`, `DAT_O`, `SEL_O`, `WE_O`,
  `CYC_O`, `STB_O`, optional `TGA_O`/`TGC_O`/`TGD_O`), and
- a **response** phase the slave returns (`DAT_I`, `ACK_I`/`ERR_I`/`RTY_I`,
  optional `TGD_I`).

The two phases are **coupled** — a classic master holds the request asserted
until the slave terminates the *same* phase. There is exactly **one outstanding
transfer** on the wire at a time (classic Wishbone is non-pipelined). So:

> **Wishbone classic = one stream = one task (`xfer(rsp, req)`) = one request
> FIFO + one response FIFO per role = one core FSM that drives a cycle and
> collects the termination.**

This is exactly the row the SKILL predicts for Wishbone. The FIFO still buys
**caller-side pipelining**: a driver can `xfer()`-queue several requests ahead of
the bus while the core grinds them out one cycle at a time, in order.

**Registered-feedback bursts (B3 ch.4, `CTI_O`/`BTE_O`)** turn the single stream
*pipelined* (one beat/cycle, slave may pre-assert `ACK`). That is the same one
stream with a deeper outstanding count — handled as a **phase-2 extension** of
the same core, not a new stream (see §8).

### Mapping streams → roles
| Role | Drives | Samples | Req FIFO | Rsp FIFO | API |
| --- | --- | --- | --- | --- | --- |
| **initiator** (master) | CYC/STB/ADR/DAT_O/WE/SEL | ACK/ERR/RTY/DAT_I | iface→core | core→iface | `xfer(rsp,req)` (blocking) |
| **target** (slave) | ACK/ERR/RTY/DAT_I | CYC/STB/ADR/DAT_O/WE/SEL | core→iface | iface→core | `access(rsp,req)` (blocking) |
| **monitor** | — (taps only) | all bus signals | core→iface | — | `observe(xfer)` (function) |

Note the target is the mirror image: its request FIFO is *filled* from the bus
and its response FIFO is *drained* to the bus — two ready/valid links, same as
the initiator but flipped.

---

## 2. Bus data types (the payload `T`)

The protocol payload is a pair of **packed structs** (packed so the core can
carry them across the internal ready/valid link as plain vectors, keeping the
core synthesizable — see SKILL design-rule "no SV queues/classes in cores").

```systemverilog
// Parameterized in the CLASS layer; FIXED (localparam) in the SV transactor
// layer — see §6 and design-rule 5 on symmetric parameterization.
//   AW = address width, DW = data width, SW = SEL width (= DW/granularity),
//   TW = aggregate user-tag width (0 if unused).
typedef struct packed {
    logic [AW-1:0] adr;
    logic [DW-1:0] dat;        // WRITE data (don't-care on reads)
    logic [SW-1:0] sel;        // byte/granule selects (RULE 3.60 qualified by STB)
    logic          we;         // 1=write, 0=read
    logic [TW-1:0] tga;        // address tag   (optional; 0-width if unused)
    logic [TW-1:0] tgc;        // cycle tag     (optional)
    logic          cyc_hold;   // keep CYC_O asserted after this beat's ACK
                               //   (block / RMW chaining — see §7). 0 ⇒ classic
                               //   single cycle (CYC drops with STB).
} wb_req_t;

typedef struct packed {
    logic [DW-1:0] dat;        // READ data (RULE 3.65: valid only at termination)
    logic          err;        // ERR_I termination
    logic          rty;        // RTY_I termination
    logic [TW-1:0] tgd;        // data tag (optional)
} wb_rsp_t;                    // ACK is implicit: a completed xfer with !err && !rty

typedef struct packed {        // monitor record = one completed phase
    wb_req_t req;
    wb_rsp_t rsp;
} wb_xfer_t;
```

**`ACK` is implicit.** Every `xfer()`/`access()` *completes* on a termination
event (`ACK`|`ERR`|`RTY`). The response therefore only needs to distinguish the
*abnormal* terminations; `ack = !err && !rty`. This keeps the common path clean
and matches RULE 3.45 (the three are mutually exclusive, so two bits suffice to
encode three outcomes plus "still running" = not-yet-returned).

Recommended defaults for the first cut (matches the `wb_dma` DUT in this repo and
the rv kit's 32-bit width): `AW=32, DW=32, SW=4` (32-bit port, byte
granularity), `TW=0` (tags off). See §9 for the 64-bit / tag open issues.

---

## 3. The class-level APIs (built per `fw-api-kit`)

Three interface classes, each shipping its `` `FW_WB_*_IMP `` macro in
`wb_proto_macros.svh` (every API ships a macro — non-negotiable per fw-api-kit
check #1).

```systemverilog
// Initiator API — issue one Wishbone transfer, block until it terminates.
interface class wb_initiator_if #(type REQ = wb_req_t, type RSP = wb_rsp_t);
    // outputs lead (rsp = xfer(req)) — see fw-api-kit "Parameter order".
    pure virtual task xfer(output RSP rsp, input REQ req);
endclass

// Target API — the model side. The target bridge hands the slave model a
// captured request and blocks for the response it should drive back.
interface class wb_target_if #(type REQ = wb_req_t, type RSP = wb_rsp_t);
    // outputs lead (rsp = access(req)).
    pure virtual task access(output RSP rsp, input REQ req);
endclass

// Monitor API — non-blocking (a function, never blocks): one completed phase.
interface class wb_monitor_if #(type XFER = wb_xfer_t);
    pure virtual function void observe(input XFER xfer);
endclass
```

Macros mirror the rv `` `FW_REQRSP_IMP `` two-method shape (every type parameter
becomes a positional macro arg; one `m_imp.NAME``_<method>` redirect per
method):

```systemverilog
`define FW_WB_INITIATOR_IMP(REQ, RSP, IMP, NAME) ...   // redirects xfer  -> NAME_xfer
`define FW_WB_TARGET_IMP(REQ, RSP, IMP, NAME)    ...   // redirects access-> NAME_access
`define FW_WB_MONITOR_IMP(XFER, IMP, NAME)       ...   // redirects observe-> NAME_observe (function)
```

> **Design choice — symmetric directionality.** Unlike rv (where initiator =
> `send`, target = `put`, two *different* one-way APIs), Wishbone is
> request/response, so **both** the initiator and target APIs are `(REQ in, RSP
> out)`. The difference is *who blocks on whom*: the initiator's `xfer` blocks on
> the bus round-trip; the target's `access` is *called by* the bridge and blocks
> the bridge until the model produces the response.

---

## 4. The six elements per role (mirrors rv exactly)

For each role the kit builds the same six things as the rv kit; the only deltas
are (a) two FIFOs/links instead of one, and (b) a bigger core FSM. File names
mirror rv (`wb_<role>_*`).

### Initiator
1. **`wb_initiator_if.svh`** — API class above.
2. **`wb_proto_macros.svh`** — the IMP macros.
3. **`wb_initiator_xtor_if.sv`** — transactor-interface. Holds a **req FIFO**
   (`xfer` pushes the request, blocks only when full) and a **rsp FIFO** (`xfer`
   then blocks popping the matching response). Two clocked blocks: one drains the
   req FIFO onto the **request up-link** (ready/valid, iface→core); one fills the
   rsp FIFO from the **response up-link** (ready/valid, core→iface). `xfer` is one
   push + one ordered pop — ordering across the pair is guaranteed because classic
   WB completes transfers in issue order.
4. **`wb_initiator_xtor_core.sv`** — the **master FSM**. Request-link consumer,
   response-link producer, Wishbone master on the pins. Per accepted request:
   assert `CYC_O`/`STB_O`, drive `ADR/DAT_O/WE/SEL/tags`, hold them stable
   (RULE 3.60) until it samples `ACK_I|ERR_I|RTY_I`; capture `DAT_I` + flags into
   a response beat, push it on the response link; drop `STB_O` (and `CYC_O` unless
   `req.cyc_hold`); return to accept. Classic = 1 outstanding.
5. **`wb_initiator_xtor.sv`** — instances iface + core, wires the two plain
   ready/valid links, exposes CLK/RST + the master pins.
6. **`wb_initiator_bridge.svh`** — provider; `` `FW_WB_INITIATOR_IMP ``;
   `exp_xfer` → `vif.xfer(rsp,req)`.

### Target (slave) — the mirror
3. **`wb_target_xtor_if.sv`** — **req FIFO** filled from the **request up-link**
   (core→iface; `recv_req` pops, blocks if empty) and **rsp FIFO** drained to the
   **response up-link** (iface→core; `send_rsp` pushes, blocks if full).
4. **`wb_target_xtor_core.sv`** — the **slave FSM**. Wishbone slave on the pins,
   request-link producer + response-link consumer. Watch `CYC_I && STB_I`; on a
   new phase capture `ADR/DAT_I/WE/SEL` into a request beat and push it up;
   **assert no termination yet** (RULE 3.35/3.50 — ACK only in response to STB);
   wait for the response beat on the response link; drive `DAT_O` + exactly one of
   `ACK_O/ERR_O/RTY_O` (RULE 3.45) until the master drops `STB_I`; return to
   watch.
6. **`wb_target_bridge.svh`** — consumer; `extends fw_port #(wb_target_if)`;
   `run()` loops: `vif.recv_req(req)` → `api.access(rsp,req)` → `vif.send_rsp(rsp)`.
   This is the rv target bridge plus the return leg.

### Monitor
4. **`wb_monitor_xtor_core.sv`** — watches the bus; on each completed phase
   (`CYC_I && STB_I && (ACK_I|ERR_I|RTY_I)`) assembles a `wb_xfer_t` (request
   *and* response sampled at the termination edge) and pushes it on a single
   ready/valid link. Drives nothing.
3/6. **`wb_monitor_xtor_if.sv` / `wb_monitor_bridge.svh`** — identical in shape to
   rv: deep FIFO (monitor can't backpressure the bus), blocking `get()`, bridge
   fans out via non-blocking `observe()`.

---

## 5. The internal link contract (unchanged from rv — this is load-bearing)

Per `fw-proto-kit` design-rules 1–4, **every interface↔core link is a plain,
clocked ready/valid handshake** (`up_valid`/`up_data`/`up_ready`) and never
speaks Wishbone. Wishbone needs **two** such links per data-carrying role:

```
initiator:  xfer_if --req link (rv)--> [master core] --WB bus--> ...
            xfer_if <--rsp link (rv)-- [master core] <--WB bus-- ...

target:     ... --WB bus--> [slave core] --req link (rv)--> xtor_if --recv_req--> bridge
            ... <--WB bus-- [slave core] <--rsp link (rv)-- xtor_if <--send_rsp-- bridge
```

Each link is a real one-beat-per-`(valid&&ready)` handshake (design-rule 2: a
registered passthrough would duplicate beats). The `up_data` of the request link
is the packed `wb_req_t`; of the response link, the packed `wb_rsp_t`. Both
endpoints clocked (design-rule 1). The cores stay queue-free and therefore
synthesizable — which is what makes the back-to-back formal proof possible (§8).

---

## 6. Parameterization strategy (design-rule 5)

Wishbone has three natural widths (AW, DW, SW) plus optional tag widths. Design
rule 5 says parameterize **symmetrically end-to-end, or not at all**, because a
parameter mangles the SV interface type and must then be threaded through every
vif handle, bridge, and wrapper.

**Recommendation:** for the first cut, fix the widths as **localparams** in the
transactor-interface/core/wrapper (exactly as rv hardcodes `[31:0]`), and define
`wb_req_t`/`wb_rsp_t` once in the package with those widths. The **class layer**
(APIs, bridges) stays parameterized `#(type REQ, type RSP)` and is width-agnostic
because it only ever moves the structs around. This gives a clean, un-mangled
`virtual wb_initiator_xtor_if` handle and zero parameter-threading risk.

Widening to 64-bit / enabling tags later is a **localparam + struct change in one
place**, not an API change — but it is *not* free per-instance configurability.
True per-instance width (a 32-bit and a 64-bit initiator in the same image) needs
full symmetric parameterization of all five SV files + the vif + the bridge; flag
that as an explicit, deferred decision (§9, open issue O-1).

---

## 7. Block, RMW, and CYC ownership — the `cyc_hold` mechanism

Classic single cycles drop `CYC_O` with `STB_O` every transfer. **Block** and
**RMW** cycles instead **hold `CYC_O` asserted across several phases** (RULE 3.25:
CYC spans the whole cycle; RMW RULE 3.85: read phase then write phase, atomic).

Rather than invent block/RMW core states, the design exposes **one extra request
bit, `cyc_hold`** (§2): the master core keeps `CYC_O` asserted after a beat's
termination iff `cyc_hold` is set, dropping only `STB_O` between phases. Then:

- **Block transfer** = N requests with `cyc_hold=1` on the first N−1 and `=0` on
  the last. A **class-layer adapter** (`wb_block_adapter`, pure component, no new
  pins — per SKILL "Adapters") sets the bits and issues the run of `xfer`s.
- **RMW** = two chained requests under one held CYC: a read (`we=0`,
  `cyc_hold=1`) immediately followed by a write (`we=1`, `cyc_hold=0`) to the same
  address. An adapter exposes `rmw(addr, f(read)->write)`.
- **`LOCK_O`** (multi-master atomicity) maps to the same idea at the arbiter
  level; expose it as an optional request bit if/when multi-master is in scope.

This keeps the core minimal and pushes block/RMW *policy* into the class layer,
which is exactly where the SKILL wants higher-level intent to live.

### The `std` memory adapter (the big win)
Per SKILL "Adapters", layer a **protocol-independent `std_mem_if`** over the
Wishbone API:

- **initiator side** — `wb_to_std`: provides `read8/16/32/64`,
  `write8/16/32/64` (+ bursts) and holds a port to `wb_initiator_if`. `read32` =
  one read `xfer`; `write32` = one write `xfer`; narrow accesses set `SEL`; wide
  accesses iterate or widen the port. Models/tests written to `std` don't change
  when the protocol is swapped.
- **target side** — `std_to_wb`: the `wb_target_bridge` calls a model that
  implements `std_mem_if` (e.g. a memory model), translating each captured
  `access(rsp,req)` into a `std` read/write and packaging the result (incl. ERR
  for unmapped addresses).

---

## 8. Formal verification — back-to-back cores (mirrors rv's `*_fv.sv`)

The kit ships a SymbiYosys proof that wires the **two synthesizable cores**
back-to-back over the Wishbone bus and drives/drains their internal ready/valid
links from **free formal inputs** — identical methodology to `rv_proto_fv.sv`.
Because Wishbone is request/response, the harness has **two** free streams (a free
request producer feeding the master's req-link + draining the slave's req-link
into a free model, and that model's free response feeding the slave's rsp-link +
the master's rsp-link drained by a free sink):

```
free req src --req link--> [master core] ==WB bus==> [slave core] --req link--> free model
free sink   <--rsp link-- [master core] <==WB bus== [slave core] <--rsp link-- free model
```

### Spec → invariants → checkers (the table the SKILL asks for)
Mined from the B3 normative rules. Each row = one small synthesizable checker in
the `` `ifdef FORMAL `` block. (rv proved rows 1–2 + 6; Wishbone adds the rest.)

| # | B3 rule (verbatim intent) | Invariant class | Checker |
| --- | --- | --- | --- |
| 1 | RULE 3.60 — master qualifies `ADR/DAT_O/SEL/WE/TAG` with `STB_O`; held until terminated | handshake stability | `$past(CYC&&STB) && !$past(ACK\|ERR\|RTY)` ⇒ `CYC&&STB && $stable(ADR,DAT_O,SEL,WE)` |
| 2 | a phase moves only on `STB && (ACK\|ERR\|RTY)` | no phantom transfer | transfer event *defined* as that AND; counters advance only on it |
| 3 | RULE 3.45 — slave asserts at most one of ACK/ERR/RTY | mutual exclusion | `assert($onehot0({ACK,ERR,RTY}))` |
| 4 | RULE 3.35/3.50 — termination generated only in response to `CYC&&STB` | framing | `assert((ACK\|ERR\|RTY) \|-> (CYC&&STB))` on the slave core |
| 5 | RULE 3.20 — `STB_O`,`CYC_O` negated under/after `RST_I` | reset | `assert(reset ⇒ !STB && !CYC)` (registered) |
| 6 | classic = one outstanding transfer | range / capacity | `assert(outstanding <= 1)` (≤ DEPTH for registered-feedback) |
| 7 | RULE 3.65 — read `DAT_I` valid at termination; request delivered & response returned unchanged, in order | conservation / integrity | anyconst `f_idx`: capture the `f_idx`-th request entering the master (`adr/dat/we/sel`); assert the `f_idx`-th request *leaving* the slave equals it, and the `f_idx`-th response returning to the master equals what the model drove |
| 8 | RULE 3.25 — `CYC_O` spans the whole cycle (no gap mid-phase) | framing | `assert($past(STB) && !term ⇒ CYC)` and CYC stable across a `cyc_hold` chain |

Building blocks are the same two the rv proof uses: `$past`/`$stable` (shadow
regs, need `read_verilog -formal`) and the `(* anyconst *)` index tracker (plain
counters/compares). **Two trackers** here — one on the request path, one on the
response path — proving the master→slave request and slave→master response are
each lossless, in-order, uncorrupted. Add a `cover` per key property (esp. that a
request *and its response* traverse end-to-end) to catch a vacuous pass, and
**inject a bug** (corrupt one captured bit) to confirm the proof has teeth — the
SKILL's mandatory "does it fail?" check. Keep BMC `depth` modest (a classic
transfer crosses in a handful of cycles; ~16–20 should let several complete).

The FileSet lists **only** `wb_initiator_xtor_core.sv` + `wb_target_xtor_core.sv`
(never the queue-based `*_xtor_if.sv`/package — yosys chokes on `logic q[$]`),
plus `wb_proto_fv.sv`, with `top: wb_proto_fv`.

---

## 8a. Back-to-back SIMULATION test — REQUIRED (not just formal)

> **Requirement.** This kit MUST ship a back-to-back *simulation* test that wires
> a full **initiator transactor** directly to a full **target transactor** over
> one shared Wishbone bus and proves data integrity end-to-end through the
> complete stack. This is a deliverable, on the same footing as the formal proof
> — the kit is not "done" until it passes.

**Why this is a distinct requirement from §8.** The back-to-back *formal* harness
deliberately drives only the synthesizable **cores** (the FIFO-based
`*_xtor_if.sv` and the bridges are not synthesizable, so yosys never sees them).
That leaves the entire **transactor-interface FIFO + bridge + class-API path
unproven**. Only a *simulation* back-to-back run exercises the full stack the user
actually instantiates:

```
driver --xfer--> [initiator bridge → xtor_if FIFO → initiator core] ==WB bus==>
        [target core → xtor_if FIFO → target bridge → slave model] --access-->
        (read data) --rsp--> ... back to the driver's xfer() return
```

This catches the class of bug formal cannot: FIFO depth/ordering errors,
bridge/`run()`-loop deadlocks, the request↔response pairing assumption (O-7),
`xfer()`/`access()` blocking semantics, and the delta-cycle/registered-handshake
rules (design-rules 1–2) as they play out across the real FIFOs.

**What the test must do (acceptance criteria):**
1. Instance `wb_initiator_xtor` and `wb_target_xtor` on one shared WB bus (plus a
   `wb_monitor_xtor` tapping it), exactly as the rv demonstrator wires its three
   transactors.
2. A driver issues a mix of **writes then reads** to the same addresses against a
   slave **memory model** (target bridge → `std_mem_if` model, §7); assert every
   read returns the previously written data — i.e. true round-trip integrity, not
   just count/order (the rv demonstrator only checks count/order because rv is
   one-way; Wishbone returns data, so the read-back check is the real proof).
3. Exercise **backpressure on both sides** (slave wait-states via delayed
   `access` return; master throttle) so the FIFOs actually fill and drain.
4. Exercise at least one **ERR** and one **RTY** termination and assert the
   response flags propagate to the `xfer()` caller unchanged.
5. Exercise a **block** and an **RMW** sequence (`cyc_hold`, §7) and assert `CYC_O`
   stays asserted across the chain (cross-checks invariant §8 row 8 in sim).
6. The **monitor** observes every completed phase; assert its record stream equals
   the driver's issued/returned sequence.
7. A watchdog `$fatal`s on hang (mirrors the rv TB) so a broken handshake fails
   fast. Expected console result: `[wb_proto] PASS`.

**Placement / target.** `tests/wb_proto_tb.sv`, run via
`dfm run wb.proto.tests.wb-proto` (the demonstrator in §10 IS this required test —
it is promoted from "example app" to "acceptance test"). Keep it the primary sim
gate alongside `dfm run wb.proto.formal.fv`.

> NOTE: the `fw-proto-kit` SKILL currently mandates back-to-back only in *formal*
> and frames the simulation side as a "demonstrator." This plan elevates
> back-to-back simulation to a hard requirement; fold that back into the SKILL
> later (tracked as a follow-up — see §9 O-9).

---

## 9. Open issues & decisions for review

### Status after implementation (2026-06-21) — reconciliation
The kit is implemented and green (sim `[wb_proto] PASS` + `[wb_std] PASS`; formal
`DONE (PASS)`, non-vacuous + teeth-checked). Open-issue dispositions:
- **O-1 (widths): DECIDED — fixed-32 implemented** in `wb_types_pkg`. Per-instance
  multi-width still deferred.
- **O-3 (ERR/RTY policy): DONE** — `wb_to_std` retries RTY (budget `RTY_MAX`) and
  escalates ERR; the low-level `xfer` still returns raw `err`/`rty`.
- **O-4 (tags): refined** — a 0-width packed member is illegal SV, so tags are
  *omitted* while disabled (not 0-width) and become real struct fields only in a
  tagged variant. `WB_TW` reserved.
- **O-9 (skill update): DONE** — back-to-back sim requirement folded into
  `fw-proto-kit/SKILL.md` (+ the O-10 sv2v `--exclude=Assert` formal note).
- **NEW O-10 — formal toolchain.** The bundled **yosys 0.9 cannot read SV
  structs/packages**, so the formal flow runs the cores+harness through
  `sv2v --exclude=Assert -DFORMAL` first. `--exclude=Assert` is **mandatory** —
  without it sv2v silently strips all assertions and the proof passes *vacuously*
  (caught only by the mandatory bug-injection teeth check). See PROPERTIES.md.
- **NEW — bug found by formal:** the slave drove a malformed `err && rty` model
  response as two terminations (RULE 3.45). Fixed with defensive priority
  `err > rty > ack` in `wb_target_xtor_core.sv`; mutual exclusion now holds
  unconditionally, and the harness `assume`s well-formed model responses for the
  end-to-end response-integrity proof. Impl refinement: bus types live in a
  standalone synthesizable **`wb_types_pkg`** (not a bare `.svh`).
- **7.3 `wb_block_adapter`: DEFERRED to stretch** — `cyc_hold` block/RMW is
  already exercised in the §8a sim and proven by formal row 8.

### Original open issues (for reference)

- **O-1 — Width parameterization (needs a call).** Recommendation §6 fixes
  AW/DW/SW as localparams (clean, un-mangled vifs, matches rv and the repo's
  32-bit `wb_dma`). The cost: no two different-width initiators in one image
  without later doing the *full* symmetric parameterization (5 SV files + vif +
  bridge). **Decision:** ship fixed-32 first, or pay the parameterization tax up
  front? I recommend fixed-32 first.

- **O-2 — Registered-feedback / burst (B3 ch.4, `CTI_O`/`BTE_O`).** The biggest
  **overlooked opportunity**: classic Wishbone is ~1 transfer per *several*
  cycles; registered feedback gives **one beat per cycle** with the slave
  pre-asserting `ACK`. It is the *same single stream* with a deeper outstanding
  count, so it fits this architecture as a **phase-2 core extension** (add
  `CTI/BTE` to `wb_req_t`, let the master pipeline up to DEPTH outstanding, add a
  range checker `outstanding <= DEPTH`). Recommend: build classic first, leave
  the struct fields reserved (`TW`-style 0-width / unused), wire CTI=`000`
  (classic) so the upgrade is additive. Flag explicitly so it isn't designed out.

- **O-3 — ERR/RTY policy.** The low-level `xfer` returns `err`/`rty` verbatim
  (correct — the core must not hide a termination). **Retry-on-RTY** and
  **error-escalation** are *policy* and belong in an adapter (e.g. `wb_to_std`
  auto-retries RTY up to N times, raises a `std` error on ERR). Confirm we want
  that split (I believe we do — it keeps the core honest and the policy testable).

- **O-4 — Tags (`TGA/TGC/TGD`).** B3 makes these user-defined and optional.
  Plan: carry a single aggregate `TW`-bit field per tag in the structs, `TW=0`
  (synthesized away) by default. Anyone needing tags sets `TW` and defines the
  field layout in *their* package. Confirm 0-width-by-default is acceptable
  (it keeps the default pinout minimal and rv-like).

- **O-5 — Asynchronous (combinational) slave ACK.** PERMISSION 3.30 lets a slave
  drive `ACK_O` combinationally from `STB_I` (one transfer per clock). Our slave
  **core** is intentionally *clocked* (design-rule 1: combinational drives are
  lost to delta races in this flow), so the kit's slave is always registered
  (≥1 wait state). That is a deliberate, spec-legal restriction, **not** a bug —
  but it means the kit slave can't model a true zero-wait-state asynchronous
  slave. Call this out to users; if a zero-wait model is required it needs a
  different (combinational) core and a careful TB, outside the standard flow.

- **O-6 — Monitor completeness at full bus rate.** Same caveat as rv: the
  monitor can't backpressure, and a 1-deep capture skid can drop beats at
  back-to-back bus rate. Size the monitor FIFO generously; document that a
  zero-drop monitor needs a deeper capture path. For registered-feedback bursts
  (O-2) this matters more (one beat/cycle) — size accordingly.

- **O-7 — Response/request ordering coupling.** The initiator `xfer` does one
  req-push then one rsp-pop; correctness relies on the bus completing transfers
  **in issue order** (true for classic and for in-order registered feedback). If
  a future variant allowed out-of-order completion (it doesn't in B3), the rsp
  FIFO would need tags to re-associate. Noted so the assumption is explicit.

- **O-8 — `wb_dma` cross-check.** This repo already contains real Wishbone RTL
  (`packages/wb_dma/rtl/verilog/wb_dma_wb_mast.v`, `…_wb_slv.v`) and bench models
  (`bench/verilog/wb_mast_model.v`, `wb_slv_model.v`). **Opportunity:** validate
  the kit's transactors against that DUT as a first real integration test (the
  kit initiator driving `wb_dma`'s slave port, the kit target backing its master
  port) — higher-value than a synthetic TB alone.

- **O-9 — Fold the back-to-back-SIM requirement back into the SKILL (follow-up).**
  §8a makes a back-to-back *simulation* integrity test a hard deliverable, but the
  `fw-proto-kit` SKILL only mandates back-to-back in *formal*. Once this kit
  proves out, update the SKILL so every kit requires both (formal on the cores +
  full-stack sim). Deferred per direction — not part of this plan's edits.

---

## 10. Proposed layout (mirrors the rv kit)

```
fw-proto-wb/
  flow.yaml                       # package wb.proto; fragments: src, tests, tests/formal
  src/
    flow.yaml                     # FileSet 'files' (kit) + 'fw-src' (fw modeling lib)
    wb_proto_pkg.sv               # import fw_pkg; include macros, type defs, APIs, bridges
    wb_proto_macros.svh           # `FW_WB_{INITIATOR,TARGET,MONITOR}_IMP
    wb_types.svh                  # wb_req_t / wb_rsp_t / wb_xfer_t (+ width localparams)
    wb_initiator_if.svh   wb_target_if.svh   wb_monitor_if.svh
    wb_initiator_bridge.svh   wb_target_bridge.svh   wb_monitor_bridge.svh
    wb_initiator_xtor_if.sv   wb_initiator_xtor_core.sv   wb_initiator_xtor.sv
    wb_target_xtor_if.sv      wb_target_xtor_core.sv      wb_target_xtor.sv
    wb_monitor_xtor_if.sv     wb_monitor_xtor_core.sv     wb_monitor_xtor.sv
    wb_to_std.svh   std_to_wb.svh   wb_block_adapter.svh   # class-layer adapters (§7)
  tests/
    flow.yaml
    wb_proto_tb.sv                # REQUIRED back-to-back sim test (§8a): init xtor ==WB==
                                  #   target xtor + monitor; write/read round-trip integrity
    formal/
      flow.yaml                   # cores FileSet + formal.sby.BMC (top: wb_proto_fv)
      wb_proto_fv.sv              # back-to-back master+slave cores; §8 checkers
      PROPERTIES.md               # the §8 table, per-kit
```

Build/run targets follow rv (`dfm run wb.proto.tests.wb-proto`,
`dfm run wb.proto.formal.fv`); expect `[wb_proto] PASS` and `DONE (PASS)`.

---

## 11. Summary of design decisions

1. **One stream, two phases** → one `xfer(rsp,req)` task, a req FIFO + rsp FIFO
   per role, one master/slave core FSM each. (SKILL's predicted Wishbone shape.)
2. **Packed-struct payload**, `ACK` implicit, ERR/RTY as response flags.
3. **Both initiator and target APIs are `(REQ in, RSP out)`** — request/response,
   unlike rv's two one-way APIs.
4. **Internal links stay plain clocked ready/valid** (two per role); cores stay
   queue-free → synthesizable → formally provable back-to-back.
5. **Block/RMW via a `cyc_hold` request bit + class-layer adapters**, not extra
   core states; **`std` memory adapter** as the protocol-independence win.
6. **Fixed 32-bit widths first** (clean vifs), parameterization deferred (O-1).
7. **Registered-feedback bursts designed-for but deferred** (O-2) — the main
   performance opportunity, additive to this architecture.
8. **Back-to-back SbY proof** with two anyconst trackers (request + response),
   mutual-exclusion/framing/reset checkers, and the mandatory bug-injection
   sanity check.
9. **Back-to-back SIMULATION test is a hard requirement** (§8a), not just the
   formal proof — it covers the FIFO/bridge/class-API stack that formal (cores
   only) cannot reach, with true write→read round-trip integrity, backpressure,
   ERR/RTY, and block/RMW. (SKILL mandates back-to-back only in formal today;
   fold this in later — O-9.)
```
