# JIT Optimization Plan

## Current State Analysis

### What We Have

1. **IR Optimization (Complete)** ✅
   - `ir/optimize.mbt` implements O0/O1/O2/O3 with CF/CP/CSE/DCE/branch simplification
   - JIT path calls `@ir.optimize_with_level(..., O2)` in `main/run.mbt:775`

2. **Pattern Matcher System (Exists but NOT Integrated)**
   - `vcode/lower/patterns.mbt`: Table-driven rule matcher with priority system
     - Has `lower_function_optimized()` - a complete alternative lowering path
     - Generic rules: identity (add_zero, mul_one), strength reduction (mul_pow2→shl)
   - `vcode/lower/aarch64_patterns.mbt`: AArch64-specific patterns
     - MADD/MSUB/MNEG rules
     - Shifted operand rules (add_shifted, sub_shifted, and_shifted, etc.)
     - Immediate validation helpers (`is_valid_add_imm`, `is_valid_logical_imm`)
   - **Problem**: Only used in whitebox tests, NOT connected to main `lower_function()`

3. **Hand-written Instruction Fusion (Working)** ✅
   - `vcode/lower/lower_numeric.mbt` has manual pattern matching:
     - `lower_iadd`: MADD fusion via `match_mul_value()`, shifted ops via `match_shl_const_value()`
     - `lower_isub`: MSUB, MNEG, SubShifted patterns
     - `lower_band/bor/bxor`: AndShifted, OrShifted, XorShifted patterns
   - **This duplicates the pattern system logic** - two implementations of same optimizations

4. **VCode Infrastructure** ✅
   - `VCodeTerminator::BranchCmp` - compare and branch directly
   - `VCodeTerminator::BranchZero` - CBZ/CBNZ for zero/nonzero conditions
   - `AddImm(Int, Bool)` and `SubImm(Int, Bool)` for immediate operands
   - Load/store have offset fields but no complex addressing modes

---

## Phase A: Verify IR Optimization in JIT Path ✅ DONE

**Status**: Already implemented

**Location**: `main/run.mbt:775`
```moonbit
@ir.optimize_with_level(ir_func, @ir.OptLevel::from_int(2)) |> ignore
```

---

## Phase B: Immediate Operand Selection ✅ DONE

### B1: Use AddImm for Constant Operands ✅

Added `match_add_imm_value()` helper and immediate patterns in `lower_iadd`.

### B2: Add SubImm VCode Opcode ✅

Added `SubImm(Int, Bool)` to VCodeOpcode with 32/64-bit emit support.

### B3: CmpImm for Comparisons with Constants ✅

**Goal**: Use `CMP Xn, #imm` instead of `CMP Xn, Xm` when comparing to constant.

**Status**: Implemented.

Added `BranchCmpImm` terminator that uses `CMP Xn, #imm` directly instead of
loading the constant into a register. Applies when comparing with constants
in the valid 12-bit immediate range (0-4095).

---

## Phase C: Branch-on-Compare Optimization ✅ DONE

### C1: Add BranchCmp Terminator ✅

Added `BranchCmp(Reg, Reg, Cond, Bool, Int, Int)` to VCodeTerminator.
- Parameters: lhs, rhs, condition, is_64, then-block, else-block
- Emits: `CMP + B.cond` (2 instructions instead of 3)

### C2: Add BranchZero Terminator ✅

Added `BranchZero(Reg, Bool, Bool, Int, Int)` to VCodeTerminator.
- Parameters: reg, is_nonzero, is_64, then-block, else-block
- Emits: `CBZ` or `CBNZ` (1 instruction)

### C3: Lower IR Branch to BranchCmp ✅

When lowering `Brz`/`Brnz` with a comparison result:
- Detect when condition comes from `Icmp` instruction
- Use `BranchCmp` with the icmp operands directly
- Otherwise fall back to `BranchZero` for boolean conditions

### C4: Emit B.cond Instructions ✅

Updated `codegen.mbt` to emit:
- `CMP + B.cond + B` for BranchCmp (with 32/64-bit CMP based on operand type)
- `CBZ/CBNZ + B` for BranchZero

### C5: Update Register Allocation ✅

Updated `regalloc.mbt` to:
- Track BranchCmp/BranchZero uses in liveness analysis
- Rewrite BranchCmp/BranchZero registers during allocation
- Handle new terminators in all pattern matches

**Result**:
- Before: `CMP + CSET + CBNZ` (3 instructions)
- After: `CMP + B.cond` (2 instructions) or `CBZ/CBNZ` (1 instruction)

---

## Phase D: Post-Regalloc Peephole Optimizations ✅ DONE

### D1: Redundant Move Elimination ✅

Skip emitting `MOV Xn, Xn` when source and destination are the same register.
Implemented in `codegen.mbt` Move opcode handling.

### D2: Zero Register Optimization (Deferred)

Using XZR/WZR for constant 0 operations would require:
- Tracking which vregs contain 0
- Substituting XZR in operand positions
- Complex analysis not worth the benefit

**Status**: Deferred - minimal impact for AArch64

### D3: Short Jump Optimization (N/A)

AArch64 branch instructions are all 4 bytes. The offset encoding is handled
by the fixup system. No further optimization needed.

**Status**: Not applicable for AArch64

---

## Phase E: Select→CSEL Fusion ✅ DONE

### E1: SelectCmp for Fused Compare and Select ✅

**Goal**: Fuse `Icmp` + `Select` into a single `SelectCmp` operation.

**Before**:
```
CMP lhs, rhs          ; from Icmp
CSET cond_reg, cc     ; from Icmp
CMP cond_reg, #0      ; from Select
CSEL rd, true, false, NE
```

**After**:
```
CMP lhs, rhs          ; fused compare
CSEL rd, true, false, cc  ; direct condition
```

**Status**: Implemented.

Added `SelectCmp(CmpKind, Bool)` opcode that:
- Detects when select condition comes from an Icmp instruction
- Uses the Icmp operands directly for the comparison
- Emits CSEL with the original condition code (not NE)

**Result**: Saves 2 instructions when select condition comes from icmp.

---

## Implementation Summary

### Completed ✅

| Phase | Description | Impact |
|-------|-------------|--------|
| A | IR Optimization in JIT path | Baseline |
| B1-B3 | AddImm/SubImm/CmpImm immediate operands | Medium |
| C1-C5 | BranchCmp/BranchCmpImm/BranchZero terminators | **High** |
| D1 | Redundant move elimination | Low |
| Select→CSEL | SelectCmp for fused compare and select | Medium |
| Addressing | Load/store address calculation folding | Medium |

### Future Work

| Phase | Description | Impact |
|-------|-------------|--------|
| F | Register allocation for WASM locals | **Critical** |
| G | Redundant instruction elimination | Medium |
| H | Tail call optimization | **High** |
| I | Bounds check elimination | Medium |
| Pattern consolidation | Integrate patterns.mbt with lowering | Tech debt |

---

## Phase F: Register Allocation for WASM Locals (TODO)

### Problem Analysis

Current fib function output shows locals stored in memory:
```asm
; Store local 0
ldr x9, [x0, #0]       ; load stack base
ldr x10, [x0, #8]      ; load stack limit
mov w11, w8
add x12, x11, #0       ; offset calculation
add x8, x12, #4        ; bounds check
cmp x8, x10
b.ls continue
; ... trap ...
continue:
add x8, x9, x12
str w2, [x8, #0]       ; finally store!
```

**This is 10+ instructions just to store one local!**

Wasmtime uses registers directly:
```asm
mov w3, #0             ; local in register
```

### Root Cause

The IR translator (`ir/translator.mbt`) models WASM operand stack and locals as:
- Operand stack → IR values (SSA, register allocated)
- WASM locals → Memory operations through `StackStore`/`StackLoad`

This is because WASM locals are mutable and can be accessed multiple times, while SSA
values are immutable. The current approach stores locals to a runtime stack.

### Solution: Local-to-Register Promotion

**F1: Analyze local usage patterns**
- Track which locals are "simple" (no address taken, simple types)
- Identify locals that fit in registers (i32, i64, f32, f64)
- Count read/write frequency

**F2: Promote locals to SSA values**
- For simple locals: use `local.get` → just reference the current SSA value
- For `local.set`: create a new SSA value, update the mapping
- For `local.tee`: same as set but also return the value
- Use phi nodes at control flow merge points

**F3: Keep stack for complex cases**
- Locals with address taken (rare in WASM)
- Reference types that need GC interaction
- Fallback for register pressure

### Implementation Plan

1. Add `LocalValue` tracking in `Translator`:
   ```moonbit
   struct LocalState {
     current_value : Value?  // SSA value if promoted
     in_memory : Bool        // fallback to stack
   }
   locals : Array[LocalState]
   ```

2. Modify `translate_local_get`:
   - If promoted: return `locals[idx].current_value`
   - If in memory: emit `StackLoad` (current behavior)

3. Modify `translate_local_set`:
   - If promoted: update `locals[idx].current_value = new_value`
   - If in memory: emit `StackStore` (current behavior)

4. Handle control flow:
   - At block/loop entry: snapshot local state
   - At block end: reconcile with phi nodes if needed
   - For loops: may need to demote to memory if local changes in loop

### Expected Impact

**Before** (fib local access): ~10 instructions per access
**After** (register local): 0-1 instructions per access

For fib function: ~80% instruction reduction possible.

---

## Phase G: Redundant Instruction Elimination (TODO)

### Problem Analysis

Current output has sequences like:
```asm
movz x8, #0, lsl #0    ; load constant 0
mov w11, w8            ; copy to w11 (redundant!)
add x12, x11, #0       ; add 0 (no-op!)
```

### Solution: Peephole Optimization Passes

**G1: Identity operation elimination**
- `add x, y, #0` → `mov x, y` or eliminate if x==y
- `sub x, y, #0` → `mov x, y`
- `mul x, y, #1` → `mov x, y`
- `and x, y, #-1` → `mov x, y`

**G2: Redundant move elimination (extended)**
- Current: skip `mov x, x`
- Extend: propagate values through moves, eliminate chains
- `mov x, y; mov z, x` → `mov z, y` if x not used later

**G3: Constant folding at VCode level**
- `movz x8, #4; add x9, x10, x8` → `add x9, x10, #4`
- Requires tracking which vregs hold constants

### Implementation Location

Best done as a post-lowering, pre-regalloc pass on VCode:
- `vcode/lower/peephole.mbt` (new file)
- Run after `lower_function`, before `allocate_registers`

---

## Phase H: Tail Call Optimization (TODO)

### Problem Analysis

Wasmtime converts tail-recursive fib to a loop:
```asm
loop:
  cmp w3, w4
  b.hs exit
  add w3, w3, #1
  add x13, x2, x5
  mov x2, x5
  mov x5, x13
  b loop
exit:
  ret
```

Wasmoon does actual recursive call:
```asm
blr x17              ; call self
; ... restore context ...
ret
```

### WASM Tail Call Proposal

WASM has `return_call` and `return_call_indirect` instructions for explicit tail calls.
These should be compiled to:
1. Deallocate current frame
2. Jump to callee (not call)

### Self-Recursion Detection

For regular `call` that is followed by `return`:
```wasm
call $self
return
```

Can be transformed to:
1. Update arguments in place
2. Jump back to function entry

### Implementation Plan

**H1: Support explicit tail calls**
- `return_call` → reuse frame, jump to target
- `return_call_indirect` → same but indirect

**H2: Detect implicit tail calls (optional)**
- Pattern match: `call` followed by `return`
- Only for self-recursion initially
- Transform to loop at IR level

### Complexity

High - requires:
- Calling convention changes
- Frame reuse logic
- Careful handling of arguments

---

## Phase I: Bounds Check Elimination (TODO)

### Problem Analysis

Every stack access has bounds check:
```asm
ldr x9, [x0, #0]       ; stack base
ldr x10, [x0, #8]      ; stack limit
add x8, x12, #4
cmp x8, x10            ; bounds check
b.ls ok
; trap
ok:
```

### Solution: Hoist and Eliminate

**I1: Hoist checks out of loops**
- If stack size is constant within loop, check once before loop
- Move invariant checks to function entry

**I2: Eliminate redundant checks**
- If we checked offset N, no need to check offset < N
- Merge adjacent checks

**I3: Prove bounds statically**
- For simple functions, compute max stack usage
- Single check at function entry

### Implementation

This optimization becomes less critical after Phase F (register locals),
since most stack accesses will be eliminated entirely.

---

## Priority Order

1. **Phase F (Register Locals)** - Highest impact, eliminates most memory access
2. **Phase G (Peephole)** - Quick wins, cleanup redundant code
3. **Phase H (Tail Call)** - Important for recursive code
4. **Phase I (Bounds Check)** - Lower priority after F

---

## Files Modified

- `vcode/instr/instr.mbt` - Added BranchCmp, BranchCmpImm, BranchZero terminators; SubImm, SelectCmp opcodes
- `vcode/lower/lower.mbt` - Branch optimization logic, BranchCmpImm support
- `vcode/lower/lower_convert.mbt` - SelectCmp fusion for select instruction
- `vcode/lower/lower_numeric.mbt` - AddImm/SubImm patterns
- `vcode/lower/regalloc.mbt` - Liveness tracking for new terminators
- `vcode/emit/codegen.mbt` - Code generation for new terminators/opcodes, peephole opt
- `vcode/emit/instructions.mbt` - SubImm32 instruction

---

## Test Results

- All unit tests pass
- Interpreter: 62563 WAST tests pass (258/258 files)
- JIT: 62563 WAST tests pass (258/258 files)

---

## References

- AArch64 instruction reference: ARM Architecture Reference Manual
- Existing patterns: `vcode/lower/aarch64_patterns.mbt`
- Existing fusion: `vcode/lower/lower_numeric.mbt`
