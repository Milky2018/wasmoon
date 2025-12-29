# Wasmoon JIT ABI (AArch64)

This document describes the calling convention and ABI used by wasmoon's JIT compiler on AArch64.

## Calling Convention

Wasmoon uses a custom calling convention optimized for WebAssembly execution.

### Register Usage

| Register | Usage | Saved |
|----------|-------|-------|
| X0 | callee_vmctx (callee's VMContext) | Caller |
| X1 | caller_vmctx (caller's VMContext) | Caller |
| X2-X7 | Integer parameters (up to 6) | Caller |
| X8 | SRET pointer (when needed) | Caller |
| X9-X15 | Scratch (allocatable) | Caller |
| X16-X17 | IP0/IP1 (linker scratch) | Caller |
| X18 | Platform reserved | - |
| X19 | Cached callee_vmctx | Callee |
| X20-X28 | Callee-saved (allocatable) | Callee |
| X29 | Frame Pointer (FP) | Callee |
| X30 | Link Register (LR) | Callee |
| SP | Stack Pointer | - |

### Floating-Point Registers

| Register | Usage | Saved |
|----------|-------|-------|
| V0-V7 | Float parameters/returns | Caller |
| V8-V15 | Callee-saved (low 64 bits) | Callee |
| V16-V31 | Scratch (allocatable) | Caller |

### Parameter Passing

1. **VMContext**: First two parameters are always VMContext pointers
   - X0: callee's VMContext (the function being called)
   - X1: caller's VMContext (for cross-module calls)

2. **Integer parameters**: X2-X7 (up to 6 values)

3. **Float parameters**: V0-V7 (up to 8 values)
   - S0-S7 for f32
   - D0-D7 for f64

4. **Stack parameters**: When registers are exhausted, remaining parameters go on stack

### Return Values

- Integer returns: X0-X7 (up to 8 values)
- Float returns: V0-V7 (up to 8 values)
- SRET: When return values exceed capacity, X8 points to return buffer

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

### Prologue

```asm
stp x29, x30, [sp, #-16]!   // Save FP and LR
mov x29, sp                  // Set up frame pointer
mov x19, x0                  // Cache callee_vmctx
// Save callee-saved registers as needed
```

### Epilogue

```asm
// Restore callee-saved registers
ldp x29, x30, [sp], #16     // Restore FP and LR
ret                          // Return
```

## Memory Access

All memory accesses go through the VMContext:

```asm
// Load memory base from VMContext
ldr x16, [x19, #0]          // x16 = vmctx->memory_base

// Bounds check
ldr x17, [x19, #8]          // x17 = vmctx->memory_size
// ... perform bounds check ...

// Access memory
ldr w0, [x16, x_offset]     // Load from memory
```

## Indirect Calls (call_indirect)

```asm
// Load table base and size
ldr x16, [x19, #24]         // table0_base
ldr x17, [x19, #32]         // table0_elements

// Bounds check
cmp x_index, x17
b.hs trap_oob

// Load function pointer
ldr x16, [x16, x_index, lsl #3]

// Type check (if needed)
// ...

// Call
blr x16
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
