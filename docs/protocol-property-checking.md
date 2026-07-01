# Identifying Protocol Properties Worth Checking — Findings & Methodology

**Status:** Draft for review
**Scope:** How to decide *what* protocol invariants to assert (and *how*), for the
`fw-proto-*` kits. General methodology + concrete application to Wishbone B3 and the
current `wb_proto_checker`. Sources are listed at the end.

---

## 1. Why this matters

Protocol invariants belong **with the protocol** (hence `wb_proto_checker` lives in
`fw-proto-wb`, not in a VIP). A good checker is *reusable assertion IP*: drop it on any
bus instance — formal harness, sim testbench, or beside real RTL — and it enforces the
spec. The questions are: **which** properties are worth the effort, and **how** to
express them so they work in both flows (yosys/SymbiYosys immediate asserts **and**
simulation SVA). This note captures the best-practice answers.

---

## 2. The two fundamental property classes

Every protocol property is either **safety** or **liveness** — this is the first lens.

| | **Safety** ("nothing bad happens") | **Liveness** ("something good eventually happens") |
|---|---|---|
| Shape | bounded in time; an invariant or bounded-window implication | unbounded in time; an *eventually* |
| Example | `request \|-> ##[0:5] ack` (ack within 5 cycles) | `request \|-> s_eventually(ack)` (ack arrives, no bound) |
| Counterexample | a **finite** trace | an **infinite** (lasso) trace |
| Proof cost | converges fast; tools prove it readily | harder; wide cone of influence; often needs abstraction + **fairness assumptions** |
| Typical use | the bulk of bus checking (stability, framing, exclusivity, ranges, data integrity) | deadlock / starvation freedom (every request is *eventually* served) |

**Practical rule of thumb (from the literature):** write most checks as **safety**, and
convert the liveness ones you care about into **bounded liveness** — i.e. a safety
property with a deadline (`!ack [*N] |=> ack`, or `request |-> ##[1:N] ack`). Bounded
liveness catches real "stuck" bugs, proves like a safety property, and avoids the cost of
true unbounded liveness. Keep a small number of *true* liveness properties for the cases
where any bound would be arbitrary (e.g. "the bus is never permanently deadlocked").

---

## 3. A catalogue of protocol property *categories* (the "what to check" list)

These recur across Wishbone, AXI/AHB ready-valid, and the OVL checker library. Use this
as a checklist when bringing up a new protocol kit. For each, the WB-B3 status of our
current `wb_proto_checker` is noted (✅ covered, ◻ candidate/gap).

1. **Reset / initialization** — defined signals are negated during/after reset, and the
   interface starts in a known idle state. *WB:* `RULE 3.20` (CYC/STB negated after RST).
   ✅
2. **Signal stability — "hold until accepted"** — *the* canonical handshake property. A
   master/producer that has asserted a qualified request must hold the request **and** the
   qualifier **stable until the transfer completes**. *AXI:* "once VALID, hold VALID+data
   until READY." *WB:* `RULE 3.60` (ADR/DAT/SEL/WE qualified by STB, held while the phase
   is unterminated). ✅
3. **Qualification / framing** — signals are only meaningful (or only legal to act on)
   when their qualifier is asserted; terminations are only produced *in response to* a
   qualified request. *WB:* `RULE 3.35` / `RULE 3.50` (ACK/ERR generated in response to
   CYC && STB). ✅ (termination only while CYC&&STB)
4. **Mutual exclusion / one-hot** — at most one of a set of signals is active. *WB:*
   `RULE 3.45` (ACK/ERR/RTY mutually exclusive). ✅ (ACK/ERR; no RTY in this kit)
5. **Response framing / dependency direction** — *who may depend on whom.* AXI forbids
   VALID depending (combinationally) on READY, to prevent handshake deadlock. **Wishbone
   is the opposite** (`RULE 3.35`: the slave's ACK *is* generated in response to STB), so a
   WB checker must **not** import the AXI "valid independent of ready" rule. ✅ documented
   in the checker header; the framing assert encodes "term only while CYC&&STB"
6. **Ordering** — responses/data come back in the order requested (for in-order
   protocols), or carry IDs (out-of-order). *WB classic:* single-outstanding ⇒ trivially
   in order. ✅ via (7)
7. **Outstanding / range / overflow** — never more transactions in flight than allowed;
   counters/FIFO pointers never over/underflow; addresses in legal range. *WB classic:*
   single-outstanding (`outst <= 1`). ✅  (OVL analogues: `ovl_range`, `ovl_overflow`,
   `ovl_fifo_index`.)
8. **Data integrity (end-to-end)** — the data delivered equals the data sent; read-back
   equals the prior write. This is usually a *harness/scoreboard* property (needs a
   reference), not a pure bus invariant — in our kit it lives in `wb_proto_fv` (symbolic
   index tracking), not in `wb_proto_checker`. ✅ (harness)
9. **Liveness / forward progress** — every accepted request is *eventually* terminated;
   the bus never deadlocks; no channel starves. *WB:* every CYC&&STB phase eventually sees
   ACK/ERR. ✅ implemented as **bounded** liveness (terminate within `MAX_WAIT`); a
   free-environment formal proof pairs it with a peer-fairness *assume* (see §7).
10. **Value-domain / X-checks** — qualified control/data are never X/Z when sampled
    (sim), and reserved encodings are never used. ✅ (sim-side SVA: qualified controls and
    read-data not X).
11. **Tag/attribute consistency** — sideband (TAG/SEL/burst attributes) is consistent and
    held with the transfer. *WB:* SEL is covered by (2); TAGs are out of scope for this
    kit. ✅ (SEL)

> **Derivation shortcut for spec-driven protocols:** the Wishbone B3 spec is written as
> numbered **RULE / PERMISSION / OBSERVATION** statements. **Each `RULE` is a candidate
> assertion; each `PERMISSION` marks a *don't*-assert (legal latitude you must not
> over-constrain); each `OBSERVATION` is design intent / a coverage target.** Walking the
> `RULE 3.xx` list and binning every rule into the categories above is the most reliable
> way to get a complete, non-arbitrary property set.

---

## 4. How to *derive* and *structure* properties (methodology)

- **Start from the spec, not from the RTL.** Map each normative rule to a property and
  cite it (the AMBA formal-IP and OVL practice: every property block carries a spec
  reference + an error message). Our checker already cites `RULE 3.xx` per assertion —
  keep that.
- **Interface properties first, end-to-end second.** Interface/handshake invariants
  (stability, framing, exclusivity) are cheap, reusable, and catch most integration bugs.
  End-to-end properties (data integrity, ordering) need a reference model and usually
  belong in a harness/scoreboard, not the always-on checker.
- **Assertions vs. assumptions (assume–guarantee).** A property is an **assert** when the
  *DUT under check* owes it, and an **assume** when it constrains the *environment*. The
  same protocol checker can serve both roles by parameter: assert the side you're proving,
  assume the side you're relying on. (Our `wb_proto_checker` only *asserts* today; a future
  `mode` could let it *assume* the peer's obligations when proving one side in isolation.)
- **Don't over-constrain.** Over-tight assumptions are the #1 cause of *missed* bugs and
  *vacuous* passes. Constrain inputs to exactly the legal protocol envelope and no more.
- **Keep properties model-checker-friendly.** Minimise variables in antecedents, prefer
  small auxiliary logic (counters, registered history) over deep SVA where it helps the
  solver, and avoid constructs the back-end can't read (see §6).

---

## 5. Knowing when you've checked *enough* (completeness)

There is no single number, but the accepted practice combines:

- **Spec-rule coverage** — every normative `RULE` is mapped to an assertion or
  consciously waived. This is the primary, auditable completeness metric for a
  spec-defined protocol.
- **Non-vacuity / witness `cover`s** — for every key implication, add a `cover` that the
  antecedent *can* be true and the transaction *does* complete, so a green proof isn't
  vacuously green. (Our `wb_proto_fv` already has end-to-end `cover`s; the checker should
  ship matching `cover`s for "a phase starts" and "a phase terminates".)
- **Formal Coverage Analysis (FCA)** — run the formal tool's reachability/structural
  coverage (line/expression/FSM/toggle): unreachable design logic under your assumptions
  usually means you've **over-constrained**, not that the logic is dead.
- **Mutation / fault sanity** — a property set that survives no injected bug is worthless;
  spot-check by breaking the RTL and confirming the right assertion fires.

---

## 6. Expressing checkers for *both* flows (our two-layer pattern)

This is a deliberate kit convention, validated on `wb_proto_checker`:

- **Synthesizable immediate-assert layer (always on).** Single-edge
  `always @(posedge clock)` blocks, `assert(...)`, with **manually registered history**
  (no `$past`). This is what SymbiYosys/yosys read directly (after `sv2v --exclude=Assert`,
  which *preserves* asserts), and it also runs in any simulator. Avoiding `$past` and
  dual-edge `always @(posedge clk or posedge rst)` blocks matters: yosys's `async2sync`
  prep **rejects** multi-trigger `$check` cells (this is exactly why the legacy
  `fwvip_wb_checker` could not be put through the BMC flow).
- **Concurrent-SVA layer (sim, `ifdef`-gated).** `assert property` with
  `$past`/`$rose`/`|=>`, gated by `WB_PROTO_SVA`. More readable, better failure messages,
  richer temporal reach — but excluded from the yosys flow. Verilator runs it.

Same rules, two encodings: the formal flow gets the portable immediate asserts; sim can
additionally enable the SVA. Keep the two layers in lock-step (one source of truth per
rule, expressed twice).

---

## 7. Application to Wishbone B3 — implemented coverage

`wb_proto_checker` now implements the catalogue for classic ACK/ERR Wishbone, with
`RULE` citations on every assertion, in both layers (synthesizable immediate asserts for
yosys/SymbiYosys + simulation; concurrent SVA under `WB_PROTO_SVA` for sim):

| Property | Rule | Form | Status |
|---|---|---|---|
| Reset negation (CYC/STB) | 3.20 | safety | ✅ proven (BMC) |
| CYC envelope (STB ⇒ CYC) | 3.25 | safety | ✅ proven (BMC) |
| Termination framing (term only while CYC&&STB) | 3.35/3.50 | safety | ✅ proven |
| ACK/ERR mutual exclusion | 3.45 | safety | ✅ proven |
| Qualified-signal stability while unterminated | 3.60 | safety | ✅ proven |
| Single-outstanding (`outst <= 1`) | design | safety | ✅ proven |
| **Bounded forward progress** (terminate within `MAX_WAIT`) | design | bounded liveness | ✅ proven (needs peer-fairness assume, below) |
| Non-vacuity covers (phase start / ACK-term / ERR-term) | — | cover | ✅ proven (cover mode) |
| Read-data known at read termination | 3.65 | X-check | ✅ sim (SVA) |
| Qualified controls/data not X | value-domain | X-check | ✅ sim (SVA) |
| Dependency-direction note (ACK depends on STB) | 3.35 | doc | ✅ documented in the module header |

The back-to-back harness adds the internal ready/valid **link** contracts and the
end-to-end **data-integrity** round trip. Everything passes under BMC depth 24.

**Implementation notes:**

- **Forward progress needs a peer-fairness ASSUME in a free-environment proof.** In the
  back-to-back harness the slave-side model is a free input that could stall forever, so
  the harness assumes the model drains the request and provides the response within
  `MODEL_MAX` cycles (bounded stall counters → `assume`). This keeps the handshake/
  backpressure exploration intact while guaranteeing termination well inside the checker's
  `MAX_WAIT`. The check itself is parameterised (`MAX_WAIT`, `CHECK_LIVENESS`) so a
  consumer with a legitimately slow slave can widen the budget or disable it.
- **Non-vacuity is formally proven.** `dv-flow-libformal` now provides a `formal.sby.Cover`
  task (`mode cover`) alongside `BMC`; the kit's `fw.proto.wb.fv-cover` runs it on the same
  sv2v output and confirms every `cover()` (checker phase-start / ACK-term / ERR-term and
  the harness's end-to-end request/response traversal) is reachable. `cover` mode FAILS if
  any cover is unreachable, so a green `fv` (BMC asserts) plus a green `fv-cover` (all
  covers reachable) together rule out vacuous proofs.
- **X-checks are sim-only by construction** — `$isunknown` has no meaning in the yosys
  flow (no X domain), so those live in the `WB_PROTO_SVA` block.

---

## 8. Reusable takeaways for the next kit (`fw-proto-ahb`, `fw-proto-axi`, …)

- Drive the property list from the spec's normative statements; bin each into the §3
  categories; cite the source on every assertion.
- Default to **safety + bounded-liveness**; reserve true liveness for genuine
  deadlock-freedom.
- Ship a **passive, parameterised `*_proto_checker` module** with the two-layer
  (immediate-assert + `ifdef` SVA) encoding, plus `cover`s for non-vacuity.
- Mind the **dependency-direction** difference between protocols (WB ACK-depends-on-STB
  vs. AXI VALID-independent-of-READY) — don't copy assertions across protocols blindly.
- Measure completeness by **rule coverage + FCA + non-vacuity**, not by count.

---

## Sources

- Lubis EDA — [Safety vs Liveness properties in formal verification](https://lubis-eda.com/safety-vs-liveness-properties-in-formal-verification/)
- DVCon — [Forward Progress Checks in Formal Verification: Liveness vs Safety](https://dvcon-proceedings.org/wp-content/uploads/1016.pdf)
- Codasip / Semiconductor Engineering — [Formal verification best practices: investigating a deadlock](https://codasip.com/2023/09/26/formal-verification-best-practices-investigating-a-deadlock/) ([SemiEngineering mirror](https://semiengineering.com/formal-verification-best-practices-investigating-a-deadlock/))
- DiVA (thesis) — [Formal Methods in Verification of Interface and Bus Protocols](https://www.diva-portal.org/smash/get/diva2:872375/FULLTEXT01.pdf)
- dh73 — [A Formal Tale, Chapter I: AMBA (AXI Formal Verification IP)](https://github.com/dh73/A_Formal_Tale_Chapter_I_AMBA)
- Verification Academy — [AXI VALID/READY handshake assertion scenarios](https://verificationacademy.com/forums/t/in-axi-valid-ready-handshake-we-have-3-scenarios-how-to-write-assertion/39655)
- Siemens Verification Horizons — [OVL: The Free, Open Assertion Library to Jump-Start Your Formal Testbench](https://blogs.sw.siemens.com/verificationhorizons/2018/03/26/ovl-the-free-open-assertion-library-you-can-use-to-jump-start-your-formal-testbench/)
- Accellera — [Open Verification Library (OVL) Working Group](https://www.accellera.org/activities/working-groups/ovl)
- Siemens Verification Horizons — [What are Vacuous Proofs, Why They Are Bad, and How to Fix Them](https://blogs.sw.siemens.com/verificationhorizons/2017/12/06/formal-tech-tip-what-are-vacuous-proofs-why-they-are-bad-and-how-to-fix-them/)
- EDA Academy — [Formal Coverage to Improve Verification Quality](https://www.eda-academy.com/resource-en-formal-coverage-to-improve-verification-quality)
- EDN — [Don't over-constrain in formal property verification (FPV) flows](https://www.edn.com/dont-over-constrain-in-formal-property-verification-fpv-flows/)
- Wishbone B3 specification — `packages/fw-proto-wb/docs/wbspec_b3.md` (RULE/PERMISSION/OBSERVATION; esp. §3 RULEs 3.20–3.65)
