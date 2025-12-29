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

4. **VCode Infrastructure**
   - `VCodeTerminator::Branch(Reg, Int, Int)` - only takes condition register
   - `AddImm(Int, Bool)` and `SubImm(Int, Bool)` exist and are now used in lowering
   - Load/store have offset fields but no complex addressing modes

### What's Missing / Underutilized

1. **Branch terminator limitation** (HIGH IMPACT)
   - Current: `Branch(Reg, Int, Int)` forces `cmp + cset + cbnz` sequence
   - Missing: `BranchCmp`, `BranchZero` for direct `cmp + b.cond` or `cbz/cbnz`

2. **Immediate operand selection** ✅ DONE (PR #257)
   - `AddImm` and `SubImm` now used in `lower_iadd` and `lower_isub`

3. **Pattern system redundancy** (TECH DEBT)
   - Two implementations: patterns.mbt + hand-written in lower_numeric.mbt
   - Should consolidate, but hand-written code already works

4. **Missing optimizations**
   - Load/store addressing modes (base + offset fusion)
   - Select → CSEL (currently: cmp + cset + conditional moves)
   - Post-regalloc peephole (redundant moves, zero register)

---

## Phase A: Verify IR Optimization in JIT Path ✅ DONE

**Status**: Already implemented

**Location**: `main/run.mbt:775`
```moonbit
@ir.optimize_with_level(ir_func, @ir.OptLevel::from_int(2)) |> ignore
```

---

## Phase B: Immediate Operand Selection ✅ DONE (PR #257)

### B1: Use AddImm for Constant Operands ✅

Added `match_add_imm_value()` helper and immediate patterns in `lower_iadd`.

### B2: Add SubImm VCode Opcode ✅

Added `SubImm(Int, Bool)` to VCodeOpcode with 32/64-bit emit support.

### B3: CmpImm for Comparisons with Constants

**Goal**: Use `CMP Xn, #imm` instead of `CMP Xn, Xm` when comparing to constant.

**Status**: Not yet implemented. Lower priority than branch optimization.

---

## Phase C: Branch-on-Compare Optimization

### C1: Add BranchCmp Terminator

**Goal**: Emit `CMP + B.cond` instead of `CMP + CSET + CBNZ`.

**Current** (`vcode/instr/instr.mbt`):
```moonbit
pub(all) enum VCodeTerminator {
  Branch(Reg, Int, Int)  // cond_reg, then_block, else_block
  ...
}
```

**Proposed addition**:
```moonbit
pub(all) enum VCodeTerminator {
  Branch(Reg, Int, Int)           // Existing: branch on register
  BranchCmp(Reg, Reg, Cond, Int, Int)  // New: branch on comparison
  BranchCmpImm(Reg, Int64, Cond, Int, Int)  // New: branch comparing to immediate
  BranchZero(Reg, Bool, Int, Int) // New: CBZ/CBNZ (Bool = is_nonzero)
  ...
}
```

### C2: Lower IR Branch to BranchCmp

When lowering `Brz`/`Brnz` with a comparison result:
```moonbit
// If condition comes from icmp, use BranchCmp
if inst.operands[0] is defined by Icmp(cond, a, b) {
  // Emit BranchCmp(a, b, cond, then, else)
} else {
  // Fall back to Branch(cond_reg, then, else)
}
```

### C3: Emit B.cond Instructions

```moonbit
BranchCmp(rn, rm, cond, then_id, else_id) => {
  // CMP Xn, Xm
  Cmp64(rn, rm).emit(self)
  // B.cond to then_block
  emit_bcond(cond, then_id)
  // B to else_block (fallthrough optimization possible)
  emit_branch(else_id)
}

BranchZero(rn, is_nonzero, then_id, else_id) => {
  if is_nonzero {
    // CBNZ Xn, then_block
    emit_cbnz(rn, then_id)
  } else {
    // CBZ Xn, then_block
    emit_cbz(rn, then_id)
  }
  emit_branch(else_id)
}
```

**Expected improvement**:
- Before: `CMP + CSET + CBNZ` (3 instructions)
- After: `CMP + B.cond` (2 instructions) or `CBZ/CBNZ` (1 instruction)

---

## Phase D: Post-Regalloc Peephole Optimizations

### D1: Redundant Move Elimination

**Goal**: Remove `MOV Xn, Xn` after register allocation.

### D2: Zero Register Optimization

**Goal**: Use XZR/WZR when loading constant 0.

### D3: Short Jump Optimization

**Goal**: Use shorter branch encodings when possible.

---

## Implementation Priority

### High Priority - Architectural Changes
1. **C1-C3: BranchCmp/BranchZero terminators** - Critical code quality gap
   - Saves 1 instruction per branch (cmp+b.cond vs cmp+cset+cbnz)
   - Requires changes to: `instr.mbt`, `lower.mbt`, `codegen.mbt`, `regalloc.mbt`

### Completed ✅
2. **B1-B2: Immediate operands** - PR #257
   - `AddImm` and `SubImm` now used in lowering

### Lower Priority - Future Work
3. **Select → CSEL fusion** - Common in conditional code
4. **Load/store addressing modes** - Address calculation folding
5. **Post-regalloc peephole** - Redundant move elimination

### Deferred - Pattern System Consolidation
- Integrate `patterns.mbt` with hand-written lowering
- Currently both work; consolidation is tech debt not functional gap

---

## Estimated Complexity

| Phase | Effort | Impact | Key Files |
|-------|--------|--------|-----------|
| C1-C3 | High | **High** | instr.mbt, lower.mbt, codegen.mbt, regalloc |
| B1-B2 | Low | Medium | ✅ Done (PR #257) |
| Select→CSEL | Medium | Medium | lower.mbt, codegen.mbt |
| Addressing | High | Medium | lower.mbt, instr.mbt, codegen.mbt |
| Peephole | Low | Low | codegen.mbt |

---

## Success Metrics

1. **Instruction count reduction**: Compare generated code size before/after
2. **Branch sequence optimization**: Count `cmp+b.cond` vs `cmp+cset+cbnz` in output
3. **Immediate usage**: Count `add/sub/cmp` with immediate vs register operands

---

## Next Steps

### Short Term (Branch Optimization)
1. Add `BranchCmp(Reg, Reg, Cond, Int, Int)` to VCodeTerminator
2. Add `BranchZero(Reg, Bool, Int, Int)` for CBZ/CBNZ
3. Modify terminator lowering to detect `Brz(icmp(...))` patterns
4. Update register allocation to handle new terminators
5. Emit `CMP + B.cond` and `CBZ/CBNZ` in codegen

### Medium Term
1. Select → CSEL optimization
2. Load/store addressing mode optimization

---

## References

- AArch64 instruction reference: ARM Architecture Reference Manual
- Existing patterns: `vcode/lower/aarch64_patterns.mbt`
- Existing fusion: `vcode/lower/lower_numeric.mbt`
