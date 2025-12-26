// Copyright 2025

#ifndef JIT_FFI_H
#define JIT_FFI_H

#include <stdint.h>
#include <stddef.h>

// ============ JIT Context v3 (Cranelift-style ABI) ============
// New ABI passes vmctx via X0 (callee_vmctx) and X1 (caller_vmctx)
// User integer params in X2-X7 (up to 6 in registers)
// Float params in V0-V7 (S for f32, D for f64)
// X19 caches callee_vmctx for fast access within the function

// VMContext v3 - layout MUST match vcode/abi/abi.mbt constants:
//   +0:  memory_base (uint8_t*)     - High frequency: linear memory base
//   +8:  memory_size (size_t)       - High frequency: memory size in bytes
//   +16: func_table (void**)        - High frequency: function pointer array
//   +24: table0_base (void**)       - High frequency: table 0 base (fast path for call_indirect)
//   +32: table0_elements (size_t)   - Medium frequency: table 0 element count
//   +40: globals (void*)            - Medium frequency: global variable array
//   +48: tables (void***)           - Low frequency: multi-table pointer array
//   +56: table_count (int)          - Low frequency: number of tables
//   +60: func_count (int)           - Low frequency: number of functions
typedef struct {
    // High frequency fields (accessed in hot paths)
    uint8_t *memory_base;     // +0:  WebAssembly linear memory base
    size_t memory_size;       // +8:  Memory size in bytes
    void **func_table;        // +16: Array of function pointers
    void **table0_base;       // +24: Table 0 base (for fast call_indirect)

    // Medium frequency fields
    size_t table0_elements;   // +32: Number of elements in table 0
    void *globals;            // +40: Array of global variable values (WasmValue*)

    // Low frequency fields (multi-table support)
    void ***tables;           // +48: Array of table pointers (for table_idx != 0)
    int table_count;          // +56: Number of tables
    int func_count;           // +60: Number of entries in func_table
    size_t *table_sizes;      // +64: Array of table current sizes for all tables
    size_t *table_max_sizes;  // +72: Array of table max sizes (-1 = unlimited)

    // Additional fields (not accessed by JIT code directly)
    int owns_indirect_table;  // Whether this context owns table0_base (should free it)
    char **args;              // WASI: command line arguments
    int argc;                 // WASI: number of arguments
    char **envp;              // WASI: environment variables
    int envc;                 // WASI: number of env vars

    // Exception handling state
    void *exception_handler;  // Current exception handler (exception_handler_t*)
    int32_t exception_tag;    // Tag of in-flight exception
    int64_t *exception_values; // Exception payload values
    int32_t exception_value_count; // Number of exception values

    // Spilled locals for exception handling
    // When throwing, current local values are saved here so catch handlers
    // can see the values at the throw point (not the setjmp point)
    int64_t *spilled_locals;      // Saved local values
    int32_t spilled_locals_count; // Number of saved locals
} jit_context_t;

// ============ Executable Memory Functions ============
// Forward declarations for GC-managed ExecCode

int64_t wasmoon_jit_alloc_exec(int size);
int wasmoon_jit_copy_code(int64_t dest, uint8_t *src, int size);
static int wasmoon_jit_free_exec(int64_t ptr);

#endif // JIT_FFI_H
