# Status / Debug Log

This file records what’s been investigated so far for the JIT failure seen with:
`./wasmoon run examples/aead_aegis128l.wasm`

## 1) Confirmed change already made

- File: `vcode/lower/lower_call.mbt`
- Change: `call_ref` and `return_call_ref` now strip only `FUNCREF_TAG` (bit 61) using mask `0xDFFFFFFFFFFFFFFF`.
  - Previously they used `0x1FFFFFFFFFFFFFFF`, which clears bits 61–63 (also clears `EXTERNREF_TAG` and the top address bit).
  - `call_indirect` already used `0xDFFFFFFFFFFFFFFF`, so this brings `call_ref` paths in line with `call_indirect`.
- Check: `moon check` passes (there is an unrelated pre-existing warning in `vcode/regalloc/regalloc.mbt:983`).

## 2) Reproduction (still failing)

### JIT run (fast, but wrong)

Command:
`./wasmoon run examples/aead_aegis128l.wasm`

Observed output (abridged):
- `Assertion failed: (size_t) found_message_len == message_len (…/libsodium/…/aead_aegis128l.c: …)`
- `Error: JIT Trap: unreachable (...)`

Notes:
- This looks like the module is miscomputing the AEAD test vector, hits a libsodium assert, and then traps.
- Interpreter mode (`--no-jit`) is extremely slow for this workload and should be avoided for iteration.
- Reconfirmed on current HEAD: still hits the same libsodium assertion and ends in `JIT Trap: unreachable` (the trap is the assert failure path).

### Debug run

Command:
`./wasmoon run -D examples/aead_aegis128l.wasm`

Observations:
- Produces huge debug logs (IR/VCode dumps for many functions).
- Confirms: module loads (`63 functions, 8 imports`), calls `_start`, then eventually prints the same libsodium assertion text and ends in `JIT Trap: unknown trap`.

### Precompiled `.cwasm` (O0)

Commands:
- `./wasmoon compile --O 0 --output /tmp/aead0.cwasm examples/aead_aegis128l.wasm`
- `./wasmoon run /tmp/aead0.cwasm`

Observations:
- Compile succeeds.
- Running the `.cwasm` still produces `Error: JIT Trap: unknown trap` (no assertion text observed in this path).
- `./wasmoon objdump /tmp/aead0.cwasm` shows `_start` has `Frame size: 0 bytes` (and large code size), so the failure is not obviously a simple stack-frame layout crash.

## 3) Facts about the input module

From `./wasmoon disasm examples/aead_aegis128l.wasm`:
- Exports: `memory`, `_start` (func 9).
- Imports: `wasi_snapshot_preview1` functions (8 imports).
- Contains many `call_indirect` sites.
- Does **not** appear to contain wasm SIMD (`v128`) instructions (no `v128` text in the disassembly output).
- Data segment includes many libsodium test vectors and assert strings, including the failing message.

## 4) Potential JIT miscompile suspects (not proven yet)

### 4.1 i32 `not` lowering/emission looks width-ambiguous (FIXED)

**Status: FIXED** - The fix has been implemented and regression tests added.

**Changes made:**
- `vcode/instr/instr.mbt`: Changed `Not` to `Not(Bool)` to carry i32/i64 size info
- `vcode/emit/instructions.mbt`: Added `Mvn32(Int, Int)` instruction with 32-bit encoding (b3=0x2A)
- `vcode/lower/lower_numeric.mbt`: Updated `lower_unary_int` to pass `is_64` flag based on result type
- `vcode/lower/lower.mbt`: Updated `Bnot` lowering to use `Not(is_64)`
- `vcode/emit/codegen.mbt`: Updated `Not` emission to call `emit_mvn32` for i32
- `testsuite/i32_not_test.mbt`: Added 5 regression tests for i32.not + br_if semantics

**Original issue:**
- IR opcode `Bnot` lowered to VCode opcode `Not` without encoding whether the value is i32 or i64.
- In the emitter, `Not` always emitted 64-bit `MVN` (`mvn xD, xN`).
- This broke the "zero means zero" invariant for i32 values when used with `BranchZero`.

**Result:** All 5 regression tests pass, but the aead_aegis128l.wasm issue persists - the root cause is elsewhere.

### 4.2 Inconsistency spotted in WAST runner funcref decoding (likely separate issue)

- `wast/runner.mbt` decodes a non-null JIT funcref as:
  - `func_idx = (v & 0x1FFFFFFFFFFFFFFF).to_int()`
- But `IRBuilder::get_func_ref` / `lower_get_func_ref` (and JIT table init) produce **tagged function pointers**
  (`func_ptr | FUNCREF_TAG`), not “function indices”.

Additional inconsistency:
- `wast/runner.mbt` decodes `ExternRef` as `(v >> 1).to_int()`, but the documented encoding is
  `EXTERNREF_TAG | (host_idx << 1)`; shifting without clearing `EXTERNREF_TAG` produces a wrong (tag-polluted) index.

This looks suspicious/inconsistent, but it’s in the WAST runner path and may be unrelated to the libsodium example.

### 4.3 AArch64 instruction-selection patterns are not i32-safe (high confidence)

There are several AArch64-specific VCode opcodes used by lowering that do **not** carry i32/i64 width,
and their emitters/encoders are effectively 64-bit (`X`-register) operations:

- Shifted-operand patterns: `AddShifted/SubShifted/AndShifted/OrShifted/XorShifted`
- Multiply-accumulate patterns: `Madd/Msub/Mneg`

Lowering currently applies these patterns for `i32` IR ops as well as `i64` ops.
This can break the implicit invariant relied on by `BranchZero` codegen:

- `BranchZero` always emits 64-bit `CBZ/CBNZ` and assumes i32 values are zero-extended so that
  “low 32 bits are zero” implies the full 64-bit register is zero.

Concrete failure mode (minimal example):
- `i32.add(0x80000000, (1 << 31))` should wrap to `0` in i32.
- If lowered via 64-bit `ADD (shifted)`, the register value becomes `0x0000000100000000`:
  low 32 bits are zero, but the 64-bit value is non-zero.
- A subsequent `br_if`/`brnz` using `BranchZero` would branch incorrectly.

This class of bug could plausibly explain “wrong result + later trap” behavior in real programs (like libsodium),
especially when integer values are used directly as boolean conditions.

Progress:
- Added `testsuite/i32_shifted_pattern_test.mbt` to cover:
  - i32 shift-amount masking with `shift=32` under `add`/`and` (pattern must not use raw `#32`)
  - i32 boolean via `br_if` where upper 32-bit garbage would flip `CBNZ` decisions
- Current result: `moon test -p testsuite -f i32_shifted_pattern_test.mbt` passes.
- The libsodium `aead_aegis128l.wasm` failure still reproduces, so the root cause is likely elsewhere (or in an uncovered pattern).

## 5) Next concrete steps (planned)

1. Make AArch64 instruction-selection patterns i32-safe:
   - Easiest correctness-first option: disable `AddShifted/SubShifted/*Shifted/Madd/Msub/Mneg` patterns for i32.
   - Better performance option: add explicit 32-bit forms (and ensure i32 shift-amount masking semantics for immediates).
2. Fix `BranchZero` to respect `is_64`:
   - Emit 32-bit `CBZ/CBNZ` when `is_64=false` (so i32 boolean tests ignore garbage upper bits).
3. Add a targeted regression test that triggers the `AddShifted + BranchZero` failure mode described above.
4. Re-run `./wasmoon run examples/aead_aegis128l.wasm` (JIT) after (1)-(3).
5. (Separate) Fix `wast/runner.mbt` reference decoding (`FuncRef` is a tagged pointer, `ExternRef` must clear tag before shifting).

## 6) Trap diagnostics improvements (planned)

Goal: make `JIT Trap: unknown trap` actionable by reporting signal/PC/fault address and mapping back to the currently executing wasm function.

Plan doc:
- `docs/jit-trap-diagnostics-plan.md`

## 7) Trap diagnostics improvements (implemented + findings)

### 7.1 Fixed SIGTRAP BRK decoding

Originally `SIGTRAP` traps were reported as `unknown trap` with a bogus `brk_imm=8` because the signal handler assumed
`ucontext.pc` points to the instruction *after* `BRK` on AArch64/macOS, and was reading `pc-4`.

After changing the handler to probe both `pc` and `pc-4` and validate the `BRK` encoding before decoding the immediate:

- The libsodium reproducer now reports: `JIT Trap: unreachable (sig=SIGTRAP(5), brk_imm=0, ...)`
- The reported `pc` now points at the actual `BRK` instruction address, so the `+0x...` offset matches the `trap "unreachable"` site.

### 7.2 What the trap actually is in `aead_aegis128l.wasm`

With `--dump-on-trap`, the trap maps to wasm func 62 (`func_62`) at the function’s `trap "unreachable"` terminator.
This is the **assert-failure path**, not the underlying miscompile:

- wasm `func 62` is a “report assert + trap” helper:
  - It is called with `(msg_ptr, line_no)` and ends in `unreachable`.
  - It hardcodes `tv` and the file path `/Users/j/src/libsodium/test/default/aead_aegis128l.c` from data segment 0.
- The failing assertion is in `_start` (wasm func 9), which contains multiple `call 62; unreachable` sites.
  - The specific message pointer for the failing one decodes to:
    - `"(size_t) found_message_len == message_len"` at address `1048694`
    - line number `628`

So the remaining task is still: find the JIT miscompile that makes the AEAD test vector mismatch, which then triggers this assert.

Additional oddity observed in the JIT path:
- The assert output should include the integer line number (`%d`), but the final field prints as raw bytes (`:\\xfe\\xbe`), not digits.
  - This suggests the printf/formatting path inside the wasm libc is also misbehaving under JIT (e.g. `%d` handling or varargs frame decoding),
    which may be another symptom of the underlying miscompile.

## 8) Fixed function index mapping bug in trap handler

### Problem
When trap occurred, `find_func_by_pc` could report wrong function/offset because it iterated `Map[Int, JITFunction]` which has undefined order (by key, not by memory address).

### Fix implemented in `jit/jit_runtime.mbt`
1. Added `AddressRange` struct to store function address ranges with func_idx
2. Added `address_ranges: Array[AddressRange]` field to `JITModule`, sorted by start address
3. Rewrote `find_func_by_pc` to use binary search (O(log n) instead of O(n))
4. Populated address_ranges in `load_with_imports` and `from_single_function`

### Result
- Trap messages now correctly identify function and offset
- Example: `wasm=62 'func_62'+0xd8` now verified correct (offset matches trap instruction position)

## 9) Current investigation status

### Verified working patterns
- Large i64 constants loading (tested with AEGIS constants)
- i64.shr_u + i32.wrap_i64 patterns
- i64 bit set patterns (1 << extend_i32_u(x))
- i64 comparisons (lt_u, ge_u)

### Still failing
- `./wasmoon run examples/aead_aegis128l.wasm`
- Assertion: `(size_t) found_message_len == message_len` at line 628
- The bug is NOT related to recent changes

### Tested patterns (all pass)
- i64 arithmetic (mul, div_u)
- Shifts and rotations (rotl, rotr, shr_u)
- Memory operations with offsets
- select instruction
- Global variables
- call_indirect
- Many local variables (25 i32 + 10 i64)
- Bit set patterns (1 << extend_i32_u(x))
- i64 comparisons (lt_u, ge_u)

### Module characteristics
- 63 functions, 8 WASI imports
- _start (func_9) has 25 i32 + 10 i64 locals
- Uses i32.rotl (AES S-box implementation)
- Has deeply nested loops for test vector validation
- All 62563 WAST spec tests pass

### Next investigation directions
- Need to find the actual miscomputed value
- Consider adding tracing/logging to key functions
- May need to compare JIT vs interpreter output for specific functions
- The bug is in a pattern not covered by existing WAST tests
- Possible approach: Extract specific AEGIS functions and test in isolation
- Consider binary search on test vectors to find minimal failing case

## 10) Previous progress: fixed i32 MSUB/MADD issues (partial improvement)

### 8.1 Root cause: AArch64 `Madd/Msub/Mneg` VCode opcodes are 64-bit only

- Our `Madd/Msub/Mneg` encodings are 64-bit AArch64 instructions (`madd/msub/mneg x…`), and are **not safe for i32 values** unless we can
  *prove* both operands are correctly zero/sign-extended.
- These patterns were being used in i32 lowering:
  - `lower_iadd`: `add(x, mul(y, z)) -> Madd`
  - `lower_isub`: `sub(x, mul(y, z)) -> Msub`, `sub(0, mul(x, y)) -> Mneg`
  - `lower_rem` used `Msub` unconditionally for remainder expansion (including `i32.rem_u` in this module).

### 8.2 Fix implemented

Changes:
- `vcode/lower/lower_numeric.mbt`
  - Restrict `Madd/Msub/Mneg` patterns to `i64` only.
  - For `i32` remainder lowering, replace `MSUB` with `Mul(false)` + `Sub(false)` so the computation stays in 32-bit semantics and the result is a clean `W`-write.

### 8.3 Observable effect on the reproducer

Command:
`./wasmoon run examples/aead_aegis128l.wasm`

Now prints the correct line number in the assertion (no raw bytes):
- `Assertion failed: (size_t) found_message_len == message_len (... aead_aegis128l.c: tv: 628)`

Status:
- The module still fails the AEAD test vector and traps on the assert path (`func_62`), so there is still at least one remaining miscompile.

### 8.4 Precompiled `.cwasm` status (still failing, now a hard crash)

Commands:
- `./wasmoon compile --O 0 --output /tmp/aead0.cwasm examples/aead_aegis128l.wasm`
- `./wasmoon run /tmp/aead0.cwasm`
- `./wasmoon compile --O 2 --output /tmp/aead2.cwasm examples/aead_aegis128l.wasm`
- `./wasmoon run /tmp/aead2.cwasm`

Observed:
- Both `O0` and `O2` precompiled runs now crash with `SIGSEGV` in `_start` (wasm func 9) at different offsets.
  - This likely indicates a separate memory safety bug in the JIT/precompiled execution path (distinct from the assert miscompile in the normal JIT run).
