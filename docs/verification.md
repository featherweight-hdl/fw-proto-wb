# Verification

The kit is verified two ways: a **back-to-back formal proof** of the
synthesizable cores, and a **back-to-back simulation** test of the full stack.
Both are hard deliverables — the kit is not "done" until both pass.

## Back-to-back formal proof

The proof (`tests/formal/wb_proto_fv.sv`) wires the **two synthesizable cores**
back-to-back over the Wishbone bus and drives/drains their internal ready/valid
links from **free formal inputs**. Because Wishbone is request/response, the
harness has two free streams:

```text
free req src --req link--> [master core] ==WB bus==> [slave core] --req link--> free model
free sink   <--rsp link-- [master core] <==WB bus== [slave core] <--rsp link-- free model
```

### Properties checked

Each row is a small synthesizable checker mined from the Wishbone B3 normative
rules:

| # | Rule (intent) | Invariant class | Checker |
| --- | --- | --- | --- |
| 1 | Master qualifies `ADR/DAT_O/SEL/WE` with `STB_O`; held until terminated (RULE 3.60) | handshake stability | request stable while `CYC && STB` and not yet terminated |
| 2 | A phase moves only on `STB && (ACK\|ERR\|RTY)` | no phantom transfer | counters advance only on that event |
| 3 | Slave asserts at most one of ACK/ERR/RTY (RULE 3.45) | mutual exclusion | `assert($onehot0({ACK, ERR, RTY}))` |
| 4 | Termination only in response to `CYC && STB` (RULE 3.35/3.50) | framing | `(ACK\|ERR\|RTY) \|-> (CYC && STB)` on the slave |
| 5 | `STB_O`, `CYC_O` negated under/after `RST_I` (RULE 3.20) | reset | `reset => !STB && !CYC` |
| 6 | Classic = one outstanding transfer | range / capacity | `assert(outstanding <= 1)` |
| 7 | Read data valid at termination; request & response delivered unchanged, in order (RULE 3.65) | conservation / integrity | two `anyconst` index trackers (request path + response path) |
| 8 | `CYC_O` spans the whole cycle, stable across a `cyc_hold` chain (RULE 3.25) | framing | `$past(STB) && !term => CYC` |

Row 7 uses **two** `anyconst` trackers — one on the request path, one on the
response path — proving the master→slave request and slave→master response are
each lossless, in-order, and uncorrupted end-to-end.

### Non-vacuity and teeth

```{admonition} The proof has teeth
:class: important
A `cover` accompanies each key property (especially that a request *and its
response* traverse end-to-end) to catch a vacuous pass. The mandatory
**bug-injection** check corrupts one captured bit and confirms the proof then
**fails** (`DONE (FAIL)`). Re-run it whenever a core changes.
```

The formal FileSet lists **only** `wb_initiator_xtor_core.sv` +
`wb_target_xtor_core.sv` (never the queue-based `*_xtor_if.sv` or the package —
yosys chokes on `logic q[$]`), plus `wb_proto_fv.sv`, with `top: wb_proto_fv`.
BMC depth is kept modest (~24 cycles) so several classic transfers complete.

```bash
dfm run wb.proto.fv        # -> DONE (PASS)
```

See `tests/formal/PROPERTIES.md` for the per-kit checker table and the teeth
check.

### A bug the formal proof caught

The proof found a real defect: the slave drove a malformed `err && rty` model
response as **two** terminations (a RULE 3.45 violation). It was fixed with a
defensive priority `err > rty > ack` in `wb_target_xtor_core.sv`; mutual
exclusion now holds unconditionally, and the harness `assume`s well-formed model
responses for the end-to-end response-integrity proof.

## Back-to-back simulation

The formal harness deliberately drives only the synthesizable **cores** — the
FIFO-based `*_xtor_if.sv`, the bridges, and the class API path are *not*
synthesizable, so yosys never sees them. A **simulation** back-to-back run is the
only thing that exercises the full stack the user actually instantiates:

```text
driver --xfer--> [initiator bridge → xtor_if FIFO → initiator core] ==WB bus==>
        [target core → xtor_if FIFO → target bridge → slave model] --access-->
        (read data) --rsp--> ... back to the driver's xfer() return
```

`tests/wb_proto_tb.sv` instances `wb_initiator_xtor` and `wb_target_xtor` on one
shared bus (with a `wb_monitor_xtor` tapping it) and asserts:

1. **Round-trip integrity** — a mix of writes then reads to the same addresses
   against a slave memory model; every read returns the previously written data.
2. **Backpressure on both sides** — slave wait-states (delayed `access` return)
   and master throttle, so the FIFOs actually fill and drain.
3. **ERR and RTY** terminations propagate to the `xfer()` caller unchanged.
4. **Block and RMW** sequences (`cyc_hold`) keep `CYC_O` asserted across the
   chain (cross-checks formal row 8 in simulation).
5. **Monitor completeness** — its record stream equals the driver's
   issued/returned sequence (all 23 phases observed).
6. A **watchdog** `$fatal`s on hang so a broken handshake fails fast.

```bash
dfm run wb.proto.wb-proto   # -> [wb_proto] PASS
```

This catches the class of bug formal cannot reach: FIFO depth/ordering errors,
bridge `run()`-loop deadlocks, the request↔response pairing assumption, and the
`xfer()`/`access()` blocking semantics as they play out across the real FIFOs.
