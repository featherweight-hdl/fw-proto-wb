# Class-layer adapters

Adapters are pure class-layer components — no new pins, no changes to the
synthesizable cores. They push higher-level *policy* (retry, error escalation,
protocol independence) into the class layer where it is testable and swappable.

## The `std_mem_if` API

`std_mem_if` is a **protocol-independent** memory-access API. User/test logic and
models written against it do not change when the underlying protocol is swapped —
a per-protocol adapter bridges it to the bus. Outputs lead ("data = read(addr)").

```systemverilog
interface class std_mem_if #(type ADDR = logic [31:0],
                             type DATA = logic [31:0],
                             type STRB = logic [3:0]);
    // Write `data` (qualified by `strb`) to `addr`; err=1 on bus error.
    pure virtual task write(output bit err, input ADDR addr, input DATA data,
                            input STRB strb);
    // Read `addr` into `data`; err=1 on bus error.
    pure virtual task read(output DATA data, output bit err, input ADDR addr);
endclass
```

Here `err` is the *escalated* bus error — an `ERR` termination, or an `RTY`
budget that has been exhausted. The adapter, not the caller, owns the
retry/escalation policy.

## `wb_to_std` — initiator side

`wb_to_std` provides `std_mem_if` on top of a Wishbone **initiator**. It holds a
port to `wb_initiator_if` and translates each `read`/`write` into one Wishbone
`xfer`:

- a `read` issues a read `xfer` (`we=0`) and returns the captured data;
- a `write` issues a write `xfer` (`we=1`) qualified by the byte strobe.

It applies the ERR/RTY **policy** the low-level `xfer` deliberately leaves raw:
it **retries on `RTY`** (up to a budget, `RTY_MAX`) and **escalates `ERR`** into
the `std_mem_if` `err` flag. Models and tests written to `std_mem_if` are
untouched when the protocol changes.

## `std_to_wb` — target side

`std_to_wb` backs a Wishbone **slave** with any `std_mem_if` memory model. The
`wb_target_bridge` calls it with each captured `access(rsp, req)`; the adapter
translates the request into a `std_mem_if` `read`/`write`, drives the model, and
packages the result back into a `wb_rsp_t` (including `ERR` for an error from the
model, e.g. an unmapped address).

## The full std stack

Wiring `wb_to_std` to `std_to_wb` over a Wishbone bus produces a **std → Wishbone
→ std** path where the driver and the memory model both speak only `std_mem_if`
and never see a Wishbone signal. This is exercised by `tests/wb_std_tb.sv`:

```bash
dfm run wb.proto.wb-std     # -> [wb_std] PASS
```

```text
driver (std_mem_if) --read/write--> [wb_to_std] --xfer--> WB bus
    --access--> [std_to_wb] --read/write--> memory model (std_mem_if)
```

## Why the split

The low-level `xfer` returns `err`/`rty` **verbatim** — the core must never hide
a termination. Retry-on-RTY and error-escalation are *policy* and belong in an
adapter. This keeps the core honest (and formally provable against the raw
Wishbone rules) while keeping the policy testable in isolation.
