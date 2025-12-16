// Copyright 2025

#ifndef JIT_FFI_H
#define JIT_FFI_H

#include <stdint.h>
#include <stddef.h>

// ============ JIT Context v2 (New ABI) ============
// New ABI uses X20 as context pointer (callee-saved)
// User params in X0-X7 (AAPCS64 compatible)
// Float params in D0-D7 (AAPCS64 compatible)

// JIT Context v2 - layout MUST match vcode/abi.mbt constants:
//   +0:  func_table (void**)
//   +8:  indirect_table (void**)    - Single indirect table (table 0)
//   +16: memory_base (uint8_t*)
//   +24: memory_size (size_t)
//   +32: indirect_tables (void***)  - Array of table pointers (multi-table support)
//   +40: table_count (int)          - Number of tables
//   +48: globals (void*)            - Array of global variable values (WasmValue*)
typedef struct {
    void **func_table;        // +0:  Array of function pointers
    void **indirect_table;    // +8:  Single indirect table (table 0) - used by prologue
    uint8_t *memory_base;     // +16: WebAssembly linear memory base
    size_t memory_size;       // +24: Memory size in bytes
    // Multi-table support fields (offset +32 onwards)
    void ***indirect_tables;  // +32: Array of indirect table pointers
    int table_count;          // +40: Number of tables
    void *globals;            // +48: Array of global variable values (WasmValue*)
    // Additional fields (not accessed by JIT prologue directly)
    int func_count;           // Number of entries in func_table
    int indirect_count;       // Number of entries in indirect_table (table 0)
    int owns_indirect_table;  // Whether this context owns indirect_table (should free it)
    char **args;              // WASI: command line arguments
    int argc;                 // WASI: number of arguments
    char **envp;              // WASI: environment variables
    int envc;                 // WASI: number of env vars
} jit_context_t;

static jit_context_t *g_jit_context;

// ============ Executable Memory Functions ============
// Forward declarations for GC-managed ExecCode

int64_t wasmoon_jit_alloc_exec(int size);
int wasmoon_jit_copy_code(int64_t dest, uint8_t *src, int size);
static int wasmoon_jit_free_exec(int64_t ptr);

#endif // JIT_FFI_H