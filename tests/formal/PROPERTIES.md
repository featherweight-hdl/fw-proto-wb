# Wishbone B3 kit — invariant properties → synthesizable checkers

The worked "spec → invariants → checkers" mapping for this kit (see the
`fw-proto-kit` SKILL *"From spec to checkers"*). Every row is implemented in
`wb_proto_fv.sv` inside the `` `ifdef FORMAL `` block and proven by
`dfm run wb.proto.fv` (BMC, boolector, depth 24).

Wishbone classic, in one breath:
> A phase transfers on a cycle where `STB && (ACK|ERR|RTY)` within an asserted
> `CYC`. The master holds the STB-qualified signals (`ADR/DAT_O/SEL/WE`) stable
> from STB assertion until the slave terminates. The slave drives at most one of
> `ACK/ERR/RTY`, only in response to `CYC && STB`. Requests are delivered to the
> slave and responses returned to the master in order, none lost or corrupted.

| # | B3 rule | Invariant class | Checker in `wb_proto_fv.sv` |
| --- | --- | --- | --- |
| 1 | RULE 3.60 — master qualifies `ADR/DAT_O/SEL/WE` with `STB`; held until terminated | handshake stability | `$past(cyc&&stb) && !$past(term)` ⇒ `cyc&&stb && $stable(adr,dat_m2s,sel,we)` |
| 2 | ready/valid link rule on the two internal links | handshake stability | master rsp-link + slave req-link: `$past(valid)&&!$past(ready)` ⇒ `valid && $stable(data)` |
| 3 | RULE 3.45 — at most one of ACK/ERR/RTY | mutual exclusion | `assert(!((ack&&err)\|(ack&&rty)\|(err&&rty)))` |
| 4 | RULE 3.35/3.50 — termination only in response to `CYC&&STB` | framing | rising-edge: `term && !$past(term)` ⇒ `cyc&&stb` |
| 5 | RULE 3.20 — `STB`/`CYC` negated the cycle after `RST_I` | reset | `$past(reset)` ⇒ `!cyc && !stb` |
| 6 | classic = single outstanding on the bus | range / capacity | phase counter `outst <= 1` (inc on phase start, dec on termination) |
| 7a | request delivered to the slave unchanged, in order | conservation / integrity | anyconst `f_idx`: the `f_idx`-th request entering the master (`adr/dat/sel/we`) equals the `f_idx`-th leaving the slave |
| 7b | RULE 3.65 — response returned to the master unchanged, in order | conservation / integrity | anyconst `f_idx`: the `f_idx`-th response from the model (`dat/err/rty`) equals the `f_idx`-th arriving at the master |

Non-vacuity: two `cover`s — a tracked request and a tracked response each traverse
end to end (confirmed reachable in `mode cover`: request @ step 4, response @ step 7).

Environment assumption: `assume(!(mdl_rsp.err && mdl_rsp.rty))` — a well-formed
slave model returns at most one termination. (The slave core *also* defends
against a malformed response with priority `err > rty > ack`, so row 3 holds
unconditionally; the assume only scopes the end-to-end response-integrity proof
of row 7b, whose mapping is otherwise undefined.)

## Toolchain note (important)
The bundled yosys (0.9) cannot read SV structs/packages, and the cores use both
(shared `wb_types_pkg`). The flow therefore runs the cores + this harness through
**`sv2v --exclude=Assert -DFORMAL`** into plain Verilog before SymbiYosys:
- `--exclude=Assert` is **mandatory** — without it sv2v silently STRIPS every
  `assert`/`assume`/`cover`, yielding a vacuous always-passing proof.
- `-DFORMAL` includes the property block before conversion.
See `tests/formal/flow.yaml`.

## Teeth check (mandatory — re-run when cores change)
Inject a one-bit corruption on the slave's captured write data
(`req_data.dat <= dat_i ^ 32'h1` in `wb_target_xtor_core.sv`) and confirm sby
reports `Assert failed` / `DONE (FAIL)` at the request-integrity assertion (row
7a). Revert and confirm `DONE (PASS)`. A proof that cannot fail proves nothing —
and note that *without* `--exclude=Assert` the proof passes even with the bug.

## Bugs this proof found (during bring-up)
1. **Mutual-exclusion violation (row 3):** the slave drove whatever the model
   returned, so a malformed `err && rty` response asserted two terminations.
   Fixed by defensive priority `err > rty > ack` in `wb_target_xtor_core.sv`.

## Extending to a richer protocol (O-2 registered feedback)
Add a *range* row `outst <= DEPTH` for the pipelined outstanding count, and
per-burst *framing* on `CTI/BTE`. Replicate the integrity tracker per stream if
streams are added; classic stays the single request+response pair above.
