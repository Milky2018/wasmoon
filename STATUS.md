# Status / Debug Log

This file records what’s been investigated so far for the JIT failure seen with:
`./wasmoon run examples/aead_aegis128l.wasm`

## Repro

- `./wasmoon run examples/aead_aegis128l.wat`
  - Fails with:
    - `Assertion failed: (size_t) found_message_len == message_len (... tv: 628)`
    - `Error: JIT Trap: unreachable ... wasm=62 'func_62'+0xd8`
- `./wasmoon run --no-jit examples/aead_aegis128l.wat`
  - Succeeds (interpreter) but is very slow (~9 minutes); prints a time-like integer (value can vary).

## Initial Triage

- `./wasmoon run --dump-on-trap examples/aead_aegis128l.wat`
  - Produces `target/jit-trap-62-func_62.log`
  - `func_62` is the assert-fail helper (formats message then `trap "unreachable"`), not the root cause.
- In `examples/aead_aegis128l.wat` the failing site is in `_start`:
  - `call 62` with `(i32.const 1048694)` and `(i32.const 628)` (tv index).
  - Confirms failure is the libsodium test-vector loop hitting tv 628.

## Ground Truth Check (External Runtime)

- `wasmtime run examples/aead_aegis128l.wat` succeeds and prints `3637510000`.
  - Confirms the `.wat` program itself is valid; the mismatch is in Wasmoon (likely JIT).

## What The Module Exercises

- The libsodium AEAD entrypoints are called via `call_indirect`:
  - `call_indirect (type 10)` uses a 10-param signature (6 reg args + 4 stack args in Wasmoon v3 ABI).
  - `call_indirect (type 11)` uses a 9-param signature (6 reg args + 3 stack args).
- The module also uses bulk memory ops (`memory.copy`, `memory.fill`) heavily.

## Quick Sanity Checks Done

- Added a regression test for `call_indirect` with 10 integer args (4 stack args):
  - `testsuite/call_indirect_stack_args_test.mbt`
  - Passes (JIT vs interpreter match), so the *basic* outgoing stack-arg plumbing for 10 args seems OK.
- `wasmoon explore` sanity:
  - `func_31` (encrypt_detached) and `func_36` (decrypt_detached) show reasonable frame sizes and stack-param load offsets in generated machine code (e.g. `+512`, `+1136` base offsets).

## Opt-Level Sweep

- `./wasmoon run --O 1 examples/aead_aegis128l.wat`
  - Same failure mode as default (tv 628 → `func_62` unreachable).
- `./wasmoon run --O 3 --dump-on-trap examples/aead_aegis128l.wat`
  - Fails earlier with `wasm=39 'func_39'+0xa0` and dumps `target/jit-trap-39-func_39.log`.
- `./wasmoon run --O 0 examples/aead_aegis128l.wat`
  - Very slow in practice (did not finish within ~10–15 minutes).

## Optimizer Correctness Fix (Independent)

While investigating whether `--O` was affecting behavior, found a correctness bug in IR constant folding:

- In `ir/optimize.mbt`, some integer folds were effectively using 64-bit semantics for i32 operations
  (e.g. shift amount masking and arithmetic vs logical right shift), and unsigned div/rem didn’t
  consistently apply i32 semantics.
- Fixed by making `fold_constants` type-aware for:
  - `Ishl`, `Sshr`, `Ushr`, `Sdiv`, `Udiv`, `Srem`, `Urem` (i32 vs i64 semantics + div overflow handling).
- Also fixed related constant-folding in e-graph rules (`ir/egraph/rules_const.mbt`) to respect bit-width.
- Added regression tests in `ir/ir_wbtest.mbt` and verified `moon test -p ir` passes.

This cleanup did **not** resolve the libsodium JIT mismatch yet (still reproduces at tv 628 with default JIT).

## Next Steps

- Determine whether the bug is in:
  - IR optimizations vs lowering/regalloc/codegen, by continuing to bisect with `--O` and comparing dumped IR/VCode/MC.
  - Or a specific codegen pattern in the crypto hot path (e.g., rotate/shift/narrow loads/stores).
