# Status / Debug Log

This file records what's been investigated so far for the JIT failure seen with:
`./wasmoon run examples/aead_aegis128l.wasm`

## Repro

- `./wasmoon run examples/aead_aegis128l.wat`
  - Fails with:
    - `Assertion failed: (size_t) found_message_len == message_len (... tv: 628)`
    - `Error: JIT Trap: unreachable ... wasm=62 'func_62'+0xd8`
- `./wasmoon run --no-jit examples/aead_aegis128l.wat`
  - Succeeds (interpreter) but is very slow (~9 minutes); prints a time-like integer (value can vary).

## Latest Findings (2026-01-19)

- Fixed JIT exceptions crash in `testsuite/exceptions_test.mbt` (multi-value payload) caused by exporting `sigsetjmp` via a wrapper.
  - `sigsetjmp` must be called directly from the JIT/emitted frame; longjmp into a returned wrapper frame is undefined behavior and can SIGSEGV.

## Latest Findings (2025-01-10)

### Root Cause Identified: Register Allocator Bug

The bug is in the register allocator's handling of fixed-register constraints for call arguments.

**Symptom:**
- IR shows `call 55(v60, v61, v10)` with 3 arguments
- VCode correctly collects all 3 arguments (v36, v37, v9)
- VCode sets fixed-register constraints: v36->x2, v37->x3, v9->x4
- Machine code only sets x2 and x3, but NOT x4

**Root Cause:**
1. vreg 9 (the 3rd argument) is assigned to physical register x4
2. Before the call instruction, another instruction reuses x4 for a different value
3. At the call, the constraint processing code checks if v9 is already assigned to x4
4. It finds `assignments.get(9) = Some(x4)` and assumes no move is needed
5. But x4 no longer contains v9's value - it was clobbered!

**Evidence:**
```
[DEBUG] vreg.id=9, required_preg.index=4
[DEBUG]   assignments.get(vreg.id)=Some(x4)
[DEBUG]   spill_slots.get(vreg.id)=None
```

The register allocator thinks v9 is in x4, but x4 has been overwritten.

### Detailed Code Analysis

**Bug Location:** `vcode/regalloc/regalloc.mbt:1059-1068` in `process_constraints()`

**Problematic Code Pattern:**
```moonbit
match alloc.assignments.get(vreg.id) {
  Some(assigned_preg) =>
    if assigned_preg.index != required_preg.index {
      // Generate move from assigned to required
      edits.before.push({...})
    }
    // BUG: If assigned_preg.index == required_preg.index, no move is generated
    // Assumption: value is already in the required register
    // Reality: register may have been clobbered by another allocation!
  None => ...
}
```

**Why This Bug Occurs:**

1. **`assignments` is a static map**: It records the vreg -> preg allocation made during the allocation phase, not the dynamic state of registers during execution.

2. **Register reuse between non-overlapping intervals**: The backtracking allocator correctly identifies that v9's interval and another vreg's interval don't overlap, so it reuses x4. This is visible in debug output:
   ```
   [DEBUG record_allocation] allocating v4 to x4, span [0:-1, 0:1]
   [DEBUG record_allocation] allocating v10 to x4, span [0:2, 0:7]
   ```

3. **Constraint processing doesn't track dynamic state**: When processing the call's fixed constraint (v9 -> x4), it only checks the static assignment, not whether x4 currently holds v9's value.

**Why Simple Tests Don't Reproduce:**

The bug requires a specific pattern:
- v9's live interval ends before the call
- Another vreg is allocated to x4 after v9's interval ends
- The call has a fixed constraint requiring v9 in x4

This pattern is rare in simple tests but occurs in complex code like aead_aegis128l.

### Possible Fixes

1. **Track register contents dynamically during constraint processing**
   - Maintain a map of preg -> current vreg at each program point
   - Before assuming no move is needed, verify the register actually holds the expected value

2. **Always emit moves for fixed constraints (conservative)**
   - In `process_constraints()`, always generate a move for fixed constraints
   - Peephole optimization can later remove redundant `mov x4, x4` instructions
   - Simple but may generate unnecessary moves

3. **Pin registers for fixed constraints during allocation**
   - When a vreg has a fixed constraint, prevent that physical register from being reused
   - Requires changes to `is_reg_free()` in backtrack.mbt

4. **Extend live intervals to include fixed constraint uses**
   - Ensure v9's interval extends all the way to the call instruction
   - This would prevent x4 from being reused before the call

### Recommended Fix

Option 2 (always emit moves) is the safest and simplest:

```moonbit
// In process_constraints(), for fixed constraints:
match alloc.assignments.get(vreg.id) {
  Some(assigned_preg) => {
    // ALWAYS generate move for fixed constraints
    // Let peephole remove redundant mov rx, rx
    if assigned_preg.index != required_preg.index {
      edits.before.push({ from: assigned_preg, to: required_preg, class: vreg.class })
    } else {
      // NEW: Still emit move even if same register,
      // because register may have been clobbered
      // OR: Check if register was actually clobbered since allocation
    }
  }
  ...
}
```

A more precise fix would track which registers have been clobbered, but this requires significant changes to the allocator state tracking.

## Previous Investigation

### Initial Triage

- `./wasmoon run --dump-on-trap examples/aead_aegis128l.wat`
  - Produces `target/jit-trap-62-func_62.log`
  - `func_62` is the assert-fail helper (formats message then `trap "unreachable"`), not the root cause.
- In `examples/aead_aegis128l.wat` the failing site is in `_start`:
  - `call 62` with `(i32.const 1048694)` and `(i32.const 628)` (tv index).
  - Confirms failure is the libsodium test-vector loop hitting tv 628.

### Ground Truth Check (External Runtime)

- `wasmtime run examples/aead_aegis128l.wat` succeeds and prints `3637510000`.
  - Confirms the `.wat` program itself is valid; the mismatch is in Wasmoon (likely JIT).

### What The Module Exercises

- The libsodium AEAD entrypoints are called via `call_indirect`:
  - `call_indirect (type 10)` uses a 10-param signature (7 reg args + 3 stack args in current JIT ABI).
  - `call_indirect (type 11)` uses a 9-param signature (7 reg args + 2 stack args).
- The module also uses bulk memory ops (`memory.copy`, `memory.fill`) heavily.

### Optimizer Correctness Fix (Independent)

While investigating whether `--O` was affecting behavior, found a correctness bug in IR constant folding:

- In `ir/optimize.mbt`, some integer folds were effectively using 64-bit semantics for i32 operations
- Fixed by making `fold_constants` type-aware for: `Ishl`, `Sshr`, `Ushr`, `Sdiv`, `Udiv`, `Srem`, `Urem`
- This cleanup did **not** resolve the libsodium JIT mismatch (still reproduces at tv 628 with default JIT).
