# Status / Debug Log

This file records what's been investigated so far for the JIT failure seen with:
`./wasmoon run examples/aead_aegis128l.wat`

## Repro

- `./wasmoon run examples/aead_aegis128l.wat`
  - Fails with:
    - `Assertion failed: (size_t) found_message_len == message_len (... tv: 628)`
    - `Error: JIT Trap: unreachable ... wasm=62 'func_62'+0xd8`
- `./wasmoon run --no-jit examples/aead_aegis128l.wat`
  - Succeeds (interpreter) but is very slow (~9 minutes); prints a time-like integer (value can vary).

## Latest Findings (2026-01-19)

### Current Status

- The issue is still **unfixed**: JIT runs `examples/aead_aegis128l.wat` but fails the libsodium test-vector check at tv `628`, then traps via `func_62` (`unreachable`).
- Interpreter-only (`--no-jit`) completes successfully (slow) and prints `3325878120000` on my machine.

### What We Added (for diagnosis + smith-diff workflows)

- Added a JIT-side assert tracing hook that triggers when the program is about to abort via `call 62(..., <const line>)`.
  - It prints the failing equality operands and the tv line number.
  - Example output from `./wasmoon run examples/aead_aegis128l.wat`:
    - `[wasmoon][jit][assert] line=628 lhs=0 rhs=124`
  - This means `found_message_len` becomes `0` under JIT while the expected `message_len` is `124`.

### Git State

- WIP branch: `wip/aead-aegis128l-jit-smithdiff`
- WIP commit: `2863091` (`jit: add tracing and width fixes for smith-diff`)
  - Includes various AArch64 i32/i64 width correctness fixes (select/bitwise/narrow loads, stack-param loads), plus the assert tracer.

### smith-diff (scripts/smith_diff/run.py)

- Ran: `python3 scripts/smith_diff/run.py run --count 200 --seed-size 512 --timeout 2`
  - Result: 7 failures, but **all failures are currently “JIT unsupported module”** (wasmoon refuses to JIT those wasm-smith modules due to unsupported instructions).
  - This means the next step is to run smith-diff with a stricter wasm-smith config (disable GC/threads/relaxed-simd/etc) so the generated cases stay within the JIT-supported instruction subset.

### Notes

- Some older content below mentions a `regalloc` fixed-register constraint root cause. That was a prior hypothesis/analysis in this log and may not reflect the current investigation path.

## Additional Notes

- `func_62` is the module’s assert/abort helper: it prints the assertion message then executes `unreachable`. The actual logic bug happens earlier.
- The failing module uses `call_indirect` heavily (notably type 10 and type 11 signatures) and bulk memory ops.
- `scripts/smith_diff/run.py` is set up to diff `wasmoon` vs `wasmtime`, but the default wasm-smith config currently generates modules that our JIT rejects as “unsupported instructions”. The next step is to restrict the wasm-smith config to only features supported by the JIT, then re-run smith-diff.
