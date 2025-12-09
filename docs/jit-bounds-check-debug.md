# JIT Memory Bounds Checking Debug Summary

## Background

The task was to implement memory bounds checking for the JIT compiler to make `assert_trap` tests pass in `testsuite/data/address.wast`. Initially, 207 tests passed and 49 failed (all `assert_trap` tests expecting "out of bounds memory access").

## Changes Made

### 1. C FFI: Pass memory_size as X2 parameter

**File:** `jit/ffi_jit.c`

Modified all `wasmoon_jit_call_ctx_*` functions to pass `memory_size` as the third argument (X2 register in AArch64 calling convention):

```c
int64_t mem_size = g_jit_context ? (int64_t)g_jit_context->memory_size : 0;
int64_t result = func(func_table_ptr, mem_base, mem_size, arg0);
```

### 2. Prologue: Save memory_size to X22

**File:** `vcode/emit.mbt`

Updated the function prologue to save memory_size (passed in X2) to the callee-saved register X22:

```
// X0 = func_table_ptr -> X20
// X1 = memory_base -> X21
// X2 = memory_size -> X22
```

### 3. Add BoundsCheck VCode Instruction

**File:** `vcode/vcode.mbt`

Added new VCode opcode:
```moonbit
BoundsCheck(Int, Int)  // (offset, access_size)
```

### 4. Emit BoundsCheck in Load/Store Lowering

**File:** `vcode/lower.mbt`

Added `emit_bounds_check()` calls in `lower_load`, `lower_load_narrow`, `lower_store`, and `lower_store_narrow` functions.

### 5. BoundsCheck Code Emission

**File:** `vcode/emit.mbt`

The BoundsCheck instruction emits:
1. Zero-extend 32-bit WASM address to 64-bit (using 32-bit MOV)
2. Add offset + access_size to get end address
3. Compare with memory_size (X22)
4. Branch if in bounds (B.LS)
5. BRK #1 if out of bounds (triggers SIGTRAP)

Key implementation details:
- Uses X16/X17 as scratch registers (platform scratch, not allocatable)
- Handles unsigned 32-bit offsets correctly using `reinterpret_as_uint().to_uint64()`
- For large offsets (>4095), uses `emit_load_imm64` to load into X17

## Bugs Found and Fixed

### Bug 1: IR Optimizer DCE Removing Load Instructions

**File:** `ir/optimize.mbt`

**Problem:** The `has_side_effects()` function didn't consider Load instructions as having side effects. When a load's result was dropped (like in `(drop (i64.load8_u ...))`), DCE would remove the load entirely.

**Impact:** `assert_trap` tests with dropped load results would never trap because the load was optimized away.

**Fix:** Added all Load variants to `has_side_effects()`:
```moonbit
fn has_side_effects(inst : Inst) -> Bool {
  match inst.opcode {
    Store(_, _) | Store8(_) | Store16(_) | Store32(_) => true
    // NEW: Loads can trap on out-of-bounds access
    Load(_, _) | Load8S(_, _) | Load8U(_, _) |
    Load16S(_, _) | Load16U(_, _) | Load32S(_) | Load32U(_) => true
    Call(_) | CallIndirect(_) => true
    _ => false
  }
}
```

### Bug 2: setjmp/longjmp Compiler Optimization Issue

**File:** `jit/ffi_jit.c`

**Problem:** Without a function call before the JIT function invocation, the compiler's optimizations around setjmp/longjmp caused crashes (SIGSEGV).

**Symptoms:**
- Tests passed with debug `fprintf` statements
- Tests crashed without debug output
- `fflush(NULL)` before JIT call fixed the crash

**Workaround:** Added `fflush(NULL)` before calling JIT functions to force proper register/stack state:
```c
// Force function call before JIT to ensure proper register/stack state
// This works around some compiler optimization issue with setjmp/longjmp
fflush(NULL);
int64_t result = func(func_table_ptr, mem_base, mem_size, arg0);
```

**Root Cause (Hypothesis):** The C compiler may be making optimization assumptions that don't hold when:
1. A function called through a pointer may trigger longjmp
2. Variables modified between setjmp and the potential longjmp point

## Results

After all fixes:
- `address.wast`: **256 passed, 0 failed** (was 207 passed, 49 failed)
- All `assert_trap` tests for out-of-bounds memory access now pass

## Lessons Learned

1. **Load instructions have side effects in WASM** - They can trap, so DCE must not remove them even if results are unused.

2. **setjmp/longjmp requires careful handling** - Compiler optimizations can break code that uses setjmp/longjmp. Function calls can act as optimization barriers.

3. **Debug output can mask bugs** - The `fprintf` calls were accidentally acting as memory barriers/optimization barriers, hiding the underlying issue.

4. **AArch64 scratch registers** - X16/X17 are platform scratch registers that won't be allocated by the register allocator, making them safe to use in code emission.

## Future Work

1. Investigate the setjmp/longjmp issue more thoroughly - the `fflush(NULL)` workaround works but isn't ideal.

2. ~~Consider using `volatile` for variables modified between setjmp and longjmp.~~ **Investigated:** Using `volatile` local variables plus `__asm__ volatile("" ::: "memory")` memory barrier did NOT fix the crash. The `fflush(NULL)` call does something more than just acting as a memory/optimization barrier.

3. Run the full test suite to verify no regressions in other tests.

## Additional Investigation (Follow-up)

### MoonBit FFI Reference Counting - Not Related

Investigated whether MoonBit's FFI reference counting mechanism could be causing the setjmp/longjmp issue. Conclusion: **NOT related**.

- The crashing functions (`wasmoon_jit_call_ctx_*`) only receive `Int64` primitive types, not reference-counted MoonBit objects
- The FFI declarations that do receive `Bytes`/`FixedArray[Byte]` already have correct `#borrow` attributes

### Volatile + Memory Barrier - Insufficient

Attempted to replace `fflush(NULL)` with proper C semantics:

```c
// Variables modified after setjmp must be volatile per C standard
volatile int64_t mem_base = 0;
volatile int64_t mem_size = 0;
volatile jit_func_ctx3_i64_i64 func = NULL;

if (setjmp(g_trap_jmp_buf) != 0) { ... }

mem_base = ...;
mem_size = ...;
func = ...;

// Memory barrier to prevent compiler from reordering
__asm__ volatile("" ::: "memory");

int64_t result = func(...);
```

**Result:** Still crashed with SIGSEGV. The `fflush(NULL)` call does something beyond what volatile + memory barrier provides - possibly:
- Making a system call that forces specific register/stack state
- Affecting function prologue/epilogue generation
- Interacting with signal handling in a specific way on AArch64

### `__attribute__((optnone))` - Works!

Attempted to disable compiler optimization entirely for the function:

```c
#if defined(__clang__) || defined(__GNUC__)
__attribute__((optnone))
#endif
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_call_ctx_i64_i64(...) {
    // ... setjmp/longjmp code ...
}
```

**Result:** Tests pass! This confirms the issue is caused by compiler optimization.

### Root Cause Analysis (Updated)

The key difference from normal setjmp/longjmp usage is that **longjmp is called from a signal handler**:

```c
static void trap_signal_handler(int sig) {
    if (g_trap_active) {
        longjmp(g_trap_jmp_buf, 1);  // Called from signal handler!
    }
}
```

Normal pattern:
```c
if (setjmp(buf) != 0) { /* error */ }
some_function();  // may call longjmp(buf, 1) directly
```

Our pattern:
```c
if (setjmp(buf) != 0) { /* error */ }
jit_func();  // BRK instruction → SIGTRAP signal → signal handler calls longjmp
```

**Why this matters:**
1. Signals can interrupt at **any instruction** (including mid-optimization sequence)
2. Signal handler has its own stack frame, may clobber registers
3. longjmp restores setjmp state, but optimized code may have assumptions about register/stack state that are violated

**Current fix:** Using `__attribute__((optnone))` to disable optimization for affected functions.

**Next investigation:** Try `sigsetjmp/siglongjmp` which are designed for signal handler contexts.
