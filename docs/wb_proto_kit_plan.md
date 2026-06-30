# Wishbone B3 Protocol Kit — Implementation Plan

**Tracks:** the design in [`wb_proto_kit_design.md`](./wb_proto_kit_design.md).
**Purpose:** ordered, checkable work plan for review + progress tracking.
**Convention:** `[ ]` todo · `[~]` in progress · `[x]` done · `[!]` blocked.
Each task names its **deliverable**, the **work**, **deps**, and an **acceptance
check** (how we know it's done). Build order respects compile/elaboration deps,
mirroring the proven rv kit's bottom-up order (types → API → macros → bridges →
xtor_if → core → xtor → TB → formal → adapters → docs).

**Reference at every step:** the rv kit at
`fw-hdl/skills/fw-proto-kit/references/example/` — each Wishbone file has a
direct rv analog; build by analogy, then add the request/response second link.

**Definition of done (whole kit):**
- `dfm run wb.proto.wb-proto` → `[wb_proto] PASS` (back-to-back sim, §8a).
- `dfm run wb.proto.fv` → `DONE (PASS)`, and **fails** when a bug is
  injected (proof has teeth).
- All design open issues O-1…O-9 either resolved or explicitly deferred in docs.

---

## Progress log

- **2026-06-21** — Toolchain validated (rv reference example builds → `[rv_proto]
  PASS`). Phases 0–5 implemented: scaffolding + `wb_types_pkg` + class APIs/macros
  + initiator/target/monitor transactors (all six elements each). Full file set
  (fw library + 9 SV transactor files + class package/bridges) passes
  `verilator --lint-only` with zero warnings — **M1 met** (re-confirmed by the
  Phase 6 sim build). Impl refinement vs design: bus types live in a standalone
  synthesizable **`wb_types_pkg`** (not a bare `.svh`) so cores + class layer share
  one definition without `$unit` collisions; tags omitted while `WB_TW==0`
  (0-width packed members are illegal SV) — to reconcile in §9.3/design O-4.
  Next: Phase 6 back-to-back sim test.

- **2026-06-21** — Phase 6 complete: `tests/wb_proto_tb.sv` + memory-model slave
  wired init↔target↔monitor on one WB bus. `dfm run wb.proto.wb-proto` →
  **`[wb_proto] PASS`**. All §8a criteria green: round-trip integrity, slave/master
  backpressure, ERR + RTY (retry to completion), block + RMW (`cyc_hold` chains,
  RMW read-back = incremented value), monitor observed all 23 phases, CYC-mid-phase
  guard silent. **M2 met.** Next: Phase 8 formal proof (cores), then Phase 7
  adapters, then docs.

- **2026-06-21** — Phase 8 complete: back-to-back formal proof (`tests/formal/
  wb_proto_fv.sv`) of the two cores. `dfm run wb.proto.fv` →
  **`DONE (PASS)`** (BMC depth 24, ~20s), covers reachable (non-vacuous), and
  bug-injection confirmed teeth (`DONE (FAIL)`). Two toolchain findings: (a) yosys
  0.9 can't read SV structs/packages → flow runs `sv2v --exclude=Assert -DFORMAL`
  first (the `--exclude=Assert` is mandatory — sv2v otherwise strips all
  assertions → vacuous pass; caught only by the teeth check). (b) **Formal found a
  real bug:** the slave drove a malformed `err && rty` model response as two
  terminations (RULE 3.45 violation); fixed with defensive priority `err>rty>ack`
  in `wb_target_xtor_core.sv` (sim still PASS). **M3 met.** Remaining: Phase 7
  adapters, Phase 9 docs.

- **2026-06-21** — Phase 7 (adapters): `std_mem_if` API + `FW_STD_MEM_IMP` macro,
  `wb_to_std` (initiator-side, RTY-retry/ERR-escalation) and `std_to_wb`
  (target-side). New test `tests/wb_std_tb.sv` drives a full **std → Wishbone →
  std** stack (driver + memory model speak only std_mem_if). `dfm run
  wb.proto.wb-std` → **`[wb_std] PASS`**. 7.3 `wb_block_adapter` DEFERRED to
  Phase 10 — `cyc_hold` block/RMW is already exercised in the §8a sim and proven
  by formal row 8, so a standalone burst adapter is low-value for MVP. Next:
  Phase 9 docs.

- **2026-06-21** — Phase 9 docs: kit `README.md` (overview, build/run, formal
  toolchain note, fixed-32 widths, minimal usage snippet), and design-doc §9
  reconciliation (O-1 decided, O-3 done, O-4 refined, new O-10 toolchain + the
  formal-found bug). 9.4 SKILL update deferred (O-9). **Final regression all
  green:** `[wb_proto] PASS`, `[wb_std] PASS`, formal `DONE (PASS)`. MVP complete
  (Phases 0–9); Phase 10 stretch items remain optional.

- **2026-06-21** — O-9 closed: folded the **back-to-back simulation requirement**
  into `fw-proto-kit/SKILL.md` (new "Back-to-back simulation test (required)"
  section + intro/layout/build updates), and strengthened the formal teeth-check
  guidance with the **sv2v `--exclude=Assert`** vacuous-proof trap (O-10) for kits
  whose cores use SV structs/packages.

## Phase 0 — Scaffolding & build skeleton

Goal: an empty-but-building package so every later task has a place to land and a
green compile to protect.

- [x] **0.1 Package + fragment flow files.** Deliverable: `flow.yaml` (package
  `wb.proto`, fragments `src`, `tests`, `tests/formal`), `src/flow.yaml`,
  `tests/flow.yaml`, `tests/formal/flow.yaml`. Work: copy rv's four flow files,
  rename `rv.proto`→`wb.proto`, fix the `fw-src` relative `base` path to reach
  `fw-hdl/src` from this package, list the `wb_*` files (created later). Deps: —.
  Accept: `dfm run wb.proto.wb-proto` *fails only* on missing SV, not on
  flow/yaml errors.
- [x] **0.2 Empty package compiles.** Deliverable: `src/wb_proto_pkg.sv` importing
  `fw_pkg`, including macros + types + APIs + bridges (stubs ok). Work: mirror
  `rv_proto_pkg.sv`. Deps: 0.1. Accept: package elaborates once stubs exist
  (revisit after Phase 1–2).
- [x] **0.3 `.envrc` / IVPM sanity.** Confirm `IVPM_PACKAGES`, verilator, yosys,
  sby on PATH per the design's build notes. Deps: —. Accept: `dfm` resolves
  `hdlsim.vlt` and `formal.sby` tasks.

---

## Phase 1 — Bus types (the payload)

Goal: the packed structs every layer moves around. Get widths right once.

- [x] **1.1 `src/wb_types.svh`.** Deliverable: `wb_req_t`, `wb_rsp_t`,
  `wb_xfer_t` packed structs + width `localparam`s (`AW=32,DW=32,SW=4,TW=0`) per
  design §2. Work: write structs exactly as §2; keep `cyc_hold` and the 0-width
  tag fields (so the burst/tag upgrades are additive — O-2/O-4). Deps: 0.2.
  Accept: a throwaway `$bits(wb_req_t)` check elaborates; fields pack with no
  4-state surprises.
- [x] **1.2 Decide width policy (O-1).** Record decision (fixed-32 recommended) in
  the design doc; if parameterized is chosen instead, expand all later tasks to
  thread the params symmetrically. Deps: 1.1. Accept: O-1 marked resolved.

---

## Phase 2 — Class-layer APIs + macros (per `fw-api-kit`)

Goal: the three interface classes and their IMP macros. **Outputs-first** arg
order throughout (`xfer(rsp, req)`), per the fw-api-kit "Parameter order" rule.

- [x] **2.1 `src/wb_initiator_if.svh`.** `interface class wb_initiator_if` with
  `pure virtual task xfer(output RSP rsp, input REQ req)`. Comment params + method.
  Deps: 1.1. Accept: compiles in package.
- [x] **2.2 `src/wb_target_if.svh`.** `wb_target_if` with
  `pure virtual task access(output RSP rsp, input REQ req)`. Deps: 1.1.
- [x] **2.3 `src/wb_monitor_if.svh`.** `wb_monitor_if` with
  `pure virtual function void observe(input XFER xfer)` (non-blocking). Deps: 1.1.
- [x] **2.4 `src/wb_proto_macros.svh`.** The three `` `FW_WB_*_IMP `` macros,
  modeled on `FW_REQRSP_IMP` (every type param positional; one
  `m_imp.NAME``_<method>` redirect; outputs-first in the redirect). Deps: 2.1–2.3.
  Accept: fw-api-kit checks #1–#6 pass (macro exists per API, covers every method,
  threads every type param, no hand-rolled `implements`).

---

## Phase 3 — Initiator role (build first; it's the master)

Build the six elements. Internal links: req (iface→core) + rsp (core→iface), both
plain clocked ready/valid.

- [x] **3.1 `src/wb_initiator_xtor_if.sv`.** Req FIFO (`xfer` pushes req, blocks if
  full) + rsp FIFO (`xfer` then pops matching rsp, blocks if empty); two clocked
  blocks draining req-link / filling rsp-link. `DEPTH` localparam. Model on
  `rv_initiator_xtor_if.sv` + add the rsp link. Deps: 1.1. Accept: standalone
  elaboration; `xfer` task poll-loops on `@(posedge clock)` (design-rule 4).
- [x] **3.2 `src/wb_initiator_xtor_core.sv`.** Master FSM: accept req beat →
  assert CYC/STB, drive ADR/DAT_O/WE/SEL/tags, **hold stable** until
  ACK|ERR|RTY → capture DAT_I+flags → push rsp beat → drop STB (and CYC unless
  `req.cyc_hold`) → accept. Clocked, queue-free (synthesizable). Deps: 1.1.
  Accept: lints clean under `read_verilog -formal` (no queues/classes); single
  outstanding.
- [x] **3.3 `src/wb_initiator_xtor.sv`.** Instance 3.1+3.2, wire the two link nets,
  expose CLK/RST + master pins. Model on `rv_initiator_xtor.sv`. Deps: 3.1,3.2.
  Accept: elaborates; `u_if` reachable.
- [x] **3.4 `src/wb_initiator_bridge.svh`.** Provider via
  `` `FW_WB_INITIATOR_IMP ``; `exp_xfer(rsp,req)` → `vif.xfer(rsp,req)`. Model on
  `rv_initiator_bridge.svh`. Deps: 2.4, 3.1. Accept: package compiles with bridge.

---

## Phase 4 — Target role (mirror of initiator)

- [x] **4.1 `src/wb_target_xtor_if.sv`.** Req FIFO filled from req-link
  (`recv_req` pops, blocks if empty) + rsp FIFO drained to rsp-link (`send_rsp`
  pushes, blocks if full). Deps: 1.1. Accept: elaborates.
- [x] **4.2 `src/wb_target_xtor_core.sv`.** Slave FSM: watch CYC&STB → capture
  ADR/DAT_I/WE/SEL into req beat, push up, **assert no termination yet** → await
  rsp beat → drive DAT_O + exactly one of ACK/ERR/RTY until STB drops → watch.
  Clocked, queue-free. Deps: 1.1. Accept: never asserts ACK outside CYC&STB
  (pre-check for formal row 4); registered (≥1 wait state — O-5).
- [x] **4.3 `src/wb_target_xtor.sv`.** Instance 4.1+4.2 + link nets + slave pins.
  Deps: 4.1,4.2.
- [x] **4.4 `src/wb_target_bridge.svh`.** Consumer `extends fw_port
  #(wb_target_if)`; `run()`: `vif.recv_req(req)` → `api.access(rsp,req)` →
  `vif.send_rsp(rsp)`. Model on `rv_target_bridge.svh` + return leg. Deps: 2.4,
  4.1. Accept: package compiles.

---

## Phase 5 — Monitor role

- [x] **5.1 `src/wb_monitor_xtor_core.sv`.** Watch bus; on completed phase
  (CYC&STB&(ACK|ERR|RTY)) assemble `wb_xfer_t` (req+rsp sampled at termination),
  push on one ready/valid link; drive nothing. Model on `rv_monitor_xtor_core.sv`.
  Deps: 1.1. Accept: drives no bus signal (inputs only).
- [x] **5.2 `src/wb_monitor_xtor_if.sv`.** Deep FIFO, blocking `get()`. Model on
  rv. Deps: 1.1.
- [x] **5.3 `src/wb_monitor_xtor.sv`** + **5.4 `src/wb_monitor_bridge.svh`**
  (`run()`: `vif.get()` → `observe()`). Deps: 5.1,5.2,2.4. Accept: package
  compiles with all three roles.

**Milestone M1 — kit compiles end to end.** ✅ (lint-clean; sim-confirm in Phase 6) `wb_proto_pkg` + all 9 SV transactor
files elaborate together. Gate before Phase 6.

---

## Phase 6 — Back-to-back SIMULATION test (REQUIRED, design §8a)

Goal: the hard acceptance gate — full stack, round-trip integrity.

- [x] **6.1 Slave memory model.** A component providing `wb_target_if` (or
  `std_mem_if` via the target-side adapter) backed by an associative array; ERR on
  unmapped addr; optional wait-state delay knob. Deps: 4.4 (and 7.x if using std).
  Accept: services read/write correctly in isolation.
- [x] **6.2 `tests/wb_proto_tb.sv`.** Wire `wb_initiator_xtor` + `wb_target_xtor`
  + `wb_monitor_xtor` on one shared WB bus (model on `rv_proto_tb.sv`); driver
  issues writes then reads. Deps: M1, 6.1. Accept criteria (all of §8a):
  - [x] **6.2a Round-trip integrity** — every read returns the prior write data.
  - [x] **6.2b Backpressure both sides** — slave wait-states + master throttle;
    FIFOs observably fill/drain.
  - [x] **6.2c ERR + RTY** — at least one each; flags reach the `xfer()` caller
    unchanged.
  - [x] **6.2d Block + RMW** — `cyc_hold` chains; assert CYC stays asserted across
    the chain.
  - [x] **6.2e Monitor equality** — observed record stream == issued/returned
    sequence.
  - [x] **6.2f Watchdog** — `$fatal` on hang; clean exit prints `[wb_proto] PASS`.
- [x] **6.3 Wire into flow.** `tests/flow.yaml` SimImage+SimRun (`top:
  wb_proto_tb`). Deps: 6.2. Accept: `dfm run wb.proto.wb-proto` →
  `[wb_proto] PASS`.

**Milestone M2 — back-to-back sim green.** ✅ [wb_proto] PASS The §8a requirement met.

---

## Phase 7 — Class-layer adapters (the protocol-independence win, §7)

Can proceed in parallel with Phase 8.

- [x] **7.1 `src/wb_to_std.svh`.** Initiator-side: provides `std_mem_if`
  (`read8/16/32/64`, `write8/16/32/64`), holds a port to `wb_initiator_if`;
  `read32`=one read xfer, `write32`=one write xfer, narrow→SEL, wide→iterate.
  Include RTY auto-retry / ERR-escalation policy (O-3). Deps: 3.4. Accept: a std
  test reads back what it wrote through the WB stack.
- [x] **7.2 `src/std_to_wb.svh`.** Target-side: `wb_target_bridge` calls a model
  implementing `std_mem_if`; translate `access(rsp,req)` → std read/write, ERR on
  unmapped. Deps: 4.4. Accept: drop-in for 6.1's model.
- [~] **7.3 (DEFERRED to Phase 10 — cyc_hold already covered in sim+formal)**  ~~orig:~~  `src/wb_block_adapter.svh`.** Sets `cyc_hold` on N−1 of N beats for
  block; exposes `rmw(...)`. Deps: 3.4. Accept: 6.2d passes when driven via the
  adapter.

---

## Phase 8 — Back-to-back FORMAL proof (design §8)

- [x] **8.1 `tests/formal/wb_proto_fv.sv`.** Wire initiator core ↔ target core
  over WB bus; two free streams (req producer/model, rsp). Model on
  `rv_proto_fv.sv`. Deps: 3.2, 4.2. Accept: elaborates under `read_verilog
  -formal`.
- [x] **8.2 Checkers (§8 rows 1–8).** Implement each invariant in the `` `ifdef
  FORMAL `` block: handshake stability, no-phantom, mutual-exclusion (`$onehot0`),
  framing, reset, range (`outstanding<=1`), **two** anyconst trackers (req + rsp),
  CYC-span. Deps: 8.1. Accept: each has a matching `cover`.
- [x] **8.3 `tests/formal/flow.yaml`.** Cores-only FileSet + `formal.sby.BMC`
  (`top: wb_proto_fv`, depth ~16–20). Deps: 8.1. Accept: `dfm run
  wb.proto.fv` → `DONE (PASS)`.
- [x] **8.4 Bug-injection sanity (mandatory).** Corrupt one captured bit; confirm
  sby reports `Assert failed` / `DONE (FAIL)`; revert. Deps: 8.3. Accept:
  documented failing run → proof has teeth.
- [x] **8.5 `tests/formal/PROPERTIES.md`.** The §8 spec→invariant→checker table,
  per-kit. Deps: 8.2. Accept: every FORMAL assertion maps to a row.

**Milestone M3 — formal green + teeth-checked.** ✅ DONE (PASS)

---

## Phase 9 — Documentation

- [x] **9.1 Kit `README`.** What the kit is, the three roles, the `std` adapter,
  build/run commands, the fixed-32 default + how to widen (O-1). Deps: M2.
- [x] **9.2 Usage snippet.** Minimal provider/consumer wiring (per fw-api-kit
  "finish by showing usage"): a driver over `wb_initiator_if`, a model providing
  `wb_target_if`, `connect()`. Deps: M2.
- [x] **9.3 Design-doc reconciliation.** Update `wb_proto_kit_design.md` open
  issues to their resolved state; record any deltas found during implementation.
  Deps: M2,M3.
- [x] **9.4 (Follow-up, O-9) SKILL update — DONE.** Fold the back-to-back-SIM
  requirement into `fw-proto-kit/SKILL.md`. Out of scope for this plan; tracked
  here so it isn't lost.

---

## Phase 10 — Stretch / opportunities (post-MVP, from design §9)

- [ ] **10.1 (O-8) `wb_dma` cross-check.** Drive the repo's real `wb_dma` slave
  port with the kit initiator (and back its master port with the kit target) as a
  real-DUT integration test. High value.
- [ ] **10.2 (O-2) Registered-feedback bursts.** Add `CTI/BTE` to `wb_req_t`,
  pipeline the master to DEPTH outstanding, add `outstanding<=DEPTH` checker +
  per-burst framing. Additive to the classic core. The main performance upside.
- [ ] **10.3 (O-4) Tags.** Exercise a non-zero `TW` configuration end to end.
- [ ] **10.4 (O-1) Full width parameterization.** Only if a 32- and 64-bit
  instance must coexist in one image; thread params symmetrically across all 5 SV
  files + vif + bridge.

---

## Dependency summary (critical path)

```
0 → 1 → 2 → 3 ┐
              ├→ M1 → 6 → M2 → 9
        4 ────┤              ↘
        5 ────┘     8 → M3 ──→ (done)
              7 (parallel, needs 3/4)
              10 (post-MVP)
```
Critical path to a usable kit: **0 → 1 → 2 → 3 → 4 → 5 → M1 → 6 → M2**.
Formal (Phase 8) and adapters (Phase 7) parallel the late stages; both required
for full done, but M2 is the first "it works" gate.

## Risk notes (carry from design)
- **Delta-cycle races** (design-rule 1): every link endpoint registered — the
  classic failure mode. Watch in 3.1/3.2/4.1/4.2.
- **Duplicated beats** (design-rule 2): links are real handshakes, not registered
  passthroughs.
- **Req↔rsp pairing** (O-7): in-order completion assumed; the round-trip check
  (6.2a) is what catches a mis-pairing.
- **Formal vs sim coverage gap**: formal sees cores only — that's *why* 6.2 (full
  stack) is non-negotiable.
```
