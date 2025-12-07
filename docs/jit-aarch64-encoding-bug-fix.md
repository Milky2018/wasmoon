# JIT AArch64 Instruction Encoding Bug Fix

Date: 2025-12-07

## Problem Summary

The JIT-compiled WebAssembly code was crashing when running `benchmark.cwasm`. The crash occurred in the `$print_num` function with a `STRB` instruction attempting to write to an invalid memory address.

## Debugging Process

### Initial Symptoms

1. `simple_loop.cwasm` printed "Loop iteration" only once instead of 3 times
2. `benchmark.cwasm` crashed with `EXC_BAD_ACCESS` after printing "Running benchmark..." and "Iteration"

### Crash Analysis

Using LLDB to debug the crash:

```
Process stopped
* thread #1, stop reason = EXC_BAD_ACCESS (code=2, address=0x1feefd2b1)
    frame #0: 0x00000001001e405c
->  0x1001e405c: strb   w24, [x17, #0x1]
```

Register state at crash:
- x17 = 0x1feefd2b0 (invalid address - should be memory_base + offset)
- x21 = 0x39574130000 (memory_base - correct)
- x25 = 0x39574130000 (computed address - same as x21)

### Root Cause Discovery

Disassembling the generated code revealed:

```asm
0x1001e4054: mov    x24, #0x20                ; =32 (space character)
0x1001e4058: add    x25, x21, x19             ; x25 = memory_base + 200 (correct!)
0x1001e405c: strb   w24, [x17, #0x1]          ; BUG: uses x17 instead of x25!
```

The instruction `strb w24, [x17, #0x1]` was using register x17 as the base address instead of x25. The ADD instruction correctly computed `x25 = x21 + x19` (memory_base + offset), but the STRB instruction encoded the wrong register.

### The Encoding Bug

In `vcode/emit.mbt`, the `emit_strb_imm` function had incorrect bit field extraction:

**Buggy code:**
```moonbit
pub fn emit_strb_imm(mc : MachineCode, rt : Int, rn : Int, imm12 : Int) -> Unit {
  let imm = imm12 & 0xFFF
  let b0 = (rt & 31) | ((rn & 3) << 5)      // BUG: rn & 3 only extracts 2 bits!
  let b1 = ((rn >> 2) & 7) | ((imm & 31) << 3)  // BUG: wrong shift
  let b2 = (imm >> 5) & 127
  let b3 = 57 // 0x39
  mc.emit_inst(b0, b1, b2, b3)
}
```

### AArch64 STRB Encoding Format

```
STRB Wt, [Xn|SP, #imm]
31 30 29 28 27 26 25 24 23 22 21        10 9    5 4    0
 0  0  1  1  1  0  0  1  0  0 | imm12      | Rn     | Rt
```

In little-endian byte order:
- b0 = bits [7:0]: Rt[4:0] in bits [4:0], Rn[2:0] in bits [7:5]
- b1 = bits [15:8]: Rn[4:3] in bits [1:0], imm12[5:0] in bits [7:2]
- b2 = bits [23:16]: imm12[11:6] in bits [5:0]
- b3 = bits [31:24]: opcode 0x39

The bug was using `rn & 3` which only extracts 2 bits of Rn instead of `rn & 7` for 3 bits.

For register X25 (binary 11001):
- Buggy: `25 & 3 = 1`, encoding register X1 or similar
- Fixed: `25 & 7 = 1`, `25 >> 3 = 3`, properly encoding X25

## Files Modified

### `vcode/emit.mbt`

Fixed 10 instruction encoding functions that had the same bug pattern:

1. **`emit_ldrb_imm`** - Load byte (unsigned)
2. **`emit_ldrh_imm`** - Load half-word (unsigned)
3. **`emit_ldr_w_imm`** - Load 32-bit word
4. **`emit_strb_imm`** - Store byte
5. **`emit_strh_imm`** - Store half-word
6. **`emit_ldrsb_x_imm`** - Load signed byte to 64-bit register
7. **`emit_ldrsb_w_imm`** - Load signed byte to 32-bit register
8. **`emit_ldrsh_x_imm`** - Load signed half-word to 64-bit register
9. **`emit_ldrsh_w_imm`** - Load signed half-word to 32-bit register
10. **`emit_ldrsw_imm`** - Load signed word to 64-bit register

### Fix Pattern

For all affected functions, changed:

```moonbit
// Before (buggy)
let b0 = (rt & 31) | ((rn & 3) << 5)
let b1 = ((rn >> 2) & 7) | ((imm & 31) << 3)
let b2 = (imm >> 5) & 127

// After (fixed)
let b0 = (rt & 31) | ((rn & 7) << 5)
let b1 = ((rn >> 3) & 3) | ((imm & 63) << 2)
let b2 = (imm >> 6) & 63
```

## Verification

After the fix:

1. **`simple_loop.cwasm`** correctly outputs:
   ```
   Loop iteration
   Loop iteration
   Loop iteration
   Done!
   ```

2. **`benchmark.cwasm`** runs to completion:
   ```
   Running benchmark...
   Iteration  1/10
   Iteration  2/10
   ...
   Iteration 10/10
   Benchmark complete!
   ```

3. All 510 tests pass.

## Lessons Learned

1. **Bit field encoding requires careful attention** - The AArch64 instruction encoding spreads register fields across byte boundaries, making manual encoding error-prone.

2. **Use consistent encoding patterns** - Some functions in the codebase correctly build the instruction as a 32-bit value then extract bytes (e.g., `emit_add_imm`), while others manually compute each byte. The 32-bit approach is less error-prone:

   ```moonbit
   // Safer approach (used in emit_add_imm, emit_sub_imm, emit_ldr_imm, emit_str_imm)
   let inst = (opcode_bits) | (imm << 10) | ((rn & 31) << 5) | (rt & 31)
   mc.emit_inst(inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
   ```

3. **LLDB disassembly is invaluable** - Comparing the disassembled output with expected instructions quickly revealed which register was being encoded incorrectly.

## Related Prior Fixes (from previous session)

This debugging session also included fixes from a previous context:

1. **`emit_sub_imm` encoding bug** - Similar bit field extraction error, fixed by using 32-bit instruction building.

2. **LR (X30) not being saved** - Functions making calls via `BLR` were overwriting LR without saving it, causing incorrect returns. Fixed by detecting `CallIndirect` instructions in `collect_used_callee_saved` and adding X30 to the list of registers to save.
