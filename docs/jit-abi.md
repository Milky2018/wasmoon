This document describes the calling convention and ABI used by wasmoon’s JIT compiler on AArch64.

The current direction is to be faithful to Cranelift’s AppleAarch64 ABI, including a Cranelift-style “special VMContext parameter” and the `enable_pinned_reg()` behavior.

## Calling Convention

Wasmoon uses a custom calling convention optimized for WebAssembly execution.

### Register Usage (GPR)

| Register | Usage | Saved |
|----------|-------|-------|
| X0 | `vmctx` (VMContext special param) | Caller |
| X1-X7 | Integer user parameters (up to 7) | Caller |
| X8 | SRET pointer (when needed) | Caller |
| X9-X15 | Scratch (allocatable) | Caller |
| X16 | IP0 / codegen scratch | Caller |
| X17 | IP1 / call target scratch (indirect calls) | Caller |
| X18 | Platform reserved | - |
| X19 | Cached `func_table` (when used) | Callee |
| X20, X22-X28 | Callee-saved (allocatable) | Callee |
| X21 | Pinned VMContext register (`enable_pinned_reg`) | Callee |
| X29 | Frame Pointer (FP) | Callee |
| X30 | Link Register (LR) | Callee |
| SP | Stack Pointer | - |

Notes:
- When `enable_pinned_reg` is enabled, the prologue copies `vmctx` from `X0` into the pinned register `X21`, and subsequent VMContext-based addressing uses `X21`.
- Call lowering materializes `X0 = X21` before Wasm calls, to pass the `vmctx` special parameter.

### Floating-Point Registers

| Register | Usage | Saved |
|----------|-------|-------|
| V0-V7 | Float/SIMD parameters and returns | Caller |
| V8-V15 | Callee-saved (low 64 bits) | Callee |
| V16-V31 | Scratch (allocatable) | Caller |

### Parameter Passing

1. **VMContext**:
   - `X0`: `vmctx` (the callee’s VMContext / instance context)

2. **Integer user parameters**:
   - `X1-X7` (up to 7 values)

3. **Float/SIMD parameters**:
   - `V0-V7` (up to 8 values)
   - `S0-S7` for `f32`
   - `D0-D7` for `f64`
   - `Q0-Q7` for `v128`

4. **Stack parameters**:
   - When registers are exhausted, remaining parameters go to the stack (16-byte aligned).

### Return Values

- Integer returns: `X0-X7` (up to 8 values)
- Float returns: `V0-V7` (up to 8 values)
- SRET: when return values exceed register capacity, `X8` points to the return buffer

## VMContext Structure

The VMContext provides access to module instance data:

```c
struct VMContext {
    uint8_t*  memory_base;      // +0:  Linear memory base pointer
    size_t    memory_size;      // +8:  Memory size in bytes
    void**    func_table;       // +16: Function pointer array
    void**    table0_base;      // +24: Table 0 base (fast path)
    size_t    table0_elements;  // +32: Table 0 element count
    void*     globals;          // +40: Global variable array
    void***   tables;           // +48: Multi-table pointer array
    int       table_count;      // +56: Number of tables
    size_t*   table_sizes;      // +64: Table sizes array
};
```

### Offset Constants

```moonbit
VMCTX_MEMORY_BASE_OFFSET     = 0
VMCTX_MEMORY_SIZE_OFFSET     = 8
VMCTX_FUNC_TABLE_OFFSET      = 16
VMCTX_TABLE0_BASE_OFFSET     = 24
VMCTX_TABLE0_ELEMENTS_OFFSET = 32
VMCTX_GLOBALS_OFFSET         = 40
VMCTX_TABLES_OFFSET          = 48
VMCTX_TABLE_COUNT_OFFSET     = 56
VMCTX_TABLE_SIZES_OFFSET     = 64
```

## Function Prologue/Epilogue

### Prologue (pinned VMContext)

```asm
stp x29, x30, [sp, #-16]!   // Save FP and LR
mov x29, sp                  // Set up frame pointer
mov x21, x0                  // Pin vmctx in x21 (enable_pinned_reg)
// Save callee-saved registers as needed (e.g. x19 if func_table is cached)
```

### Epilogue

```asm
// Restore callee-saved registers
ldp x29, x30, [sp], #16     // Restore FP and LR
ret                          // Return
```

## Memory Access

All memory accesses go through the VMContext (pinned in `x21` when enabled):

```asm
// Load memory base from VMContext
ldr x16, [x21, #0]          // x16 = vmctx->memory_base

// Bounds check
ldr x17, [x21, #8]          // x17 = vmctx->memory_size
// ... perform bounds check ...

// Access memory
ldr w0, [x16, x_offset]     // Load from memory
```

## Indirect Calls (call_indirect)

```asm
// Load table base and size
ldr x16, [x21, #24]         // table0_base
ldr x17, [x21, #32]         // table0_elements

// Bounds check
cmp x_index, x17
b.hs trap_oob

// Load function pointer
ldr x17, [x16, x_index, lsl #3]

// Call (vmctx special param is passed in x0)
mov x0, x21
blr x17
```

## Traps

Traps are triggered for:
- Out-of-bounds memory access
- Out-of-bounds table access
- Integer division by zero
- Integer overflow (i32.div_s INT_MIN / -1)
- Invalid indirect call (null or type mismatch)
- Unreachable instruction

Trap handling jumps to a trap handler that unwinds the stack and reports the error.
