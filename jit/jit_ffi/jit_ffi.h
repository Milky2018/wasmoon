// Copyright 2025

// JIT execution context - holds function table and memory pointer
typedef struct {
    void **func_table;      // Array of function pointers (indexed by func_idx)
    int func_count;         // Number of entries in func_table
    void **indirect_table;  // Array for call_indirect (indexed by table element index)
    int indirect_count;     // Number of entries in indirect_table
    uint8_t *memory_base;   // WebAssembly linear memory base
    size_t memory_size;     // Memory size in bytes
    // WASI args/env storage
    char **args;            // Command line arguments
    int argc;               // Number of arguments
    char **envp;            // Environment variables (NAME=VALUE format)
    int envc;               // Number of environment variables
} jit_context_t;

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
    char **args;              // WASI: command line arguments
    int argc;                 // WASI: number of arguments
    char **envp;              // WASI: environment variables
    int envc;                 // WASI: number of env vars
} jit_context_v2_t;


static jit_context_t *g_jit_context;
static jit_context_v2_t *g_jit_context_v2;