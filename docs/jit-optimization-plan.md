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

### Future Work

| Phase | Description | Impact |
|-------|-------------|--------|
| Addressing | Load/store address calculation folding | Medium |
| Pattern consolidation | Integrate patterns.mbt with lowering | Tech debt |

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

- All 1160 unit tests pass
- Interpreter: 62563 WAST tests pass (258/258 files)
- JIT: 62561 WAST tests pass (257/258 files) - 1 pre-existing SIMD issue

---

## References

- AArch64 instruction reference: ARM Architecture Reference Manual
- Existing patterns: `vcode/lower/aarch64_patterns.mbt`
- Existing fusion: `vcode/lower/lower_numeric.mbt`
