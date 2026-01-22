// Copyright 2025

#ifndef JIT_FFI_H
#define JIT_FFI_H

#include <stdint.h>
#include <stddef.h>
#include <stdatomic.h>

// ============ JIT Context v3 ============
// New ABI passes vmctx via X0 (callee_vmctx) and X1 (caller_vmctx)
// User integer params in X2-X7 (up to 6 in registers)
// Float params in V0-V7 (S for f32, D for f64)
// X19 caches callee_vmctx for fast access within the function

// Shared linear memory definition (wasmtime-style)
// Layout is intentionally compatible with JIT-generated loads:
//   +0: base pointer
//   +8: current length in bytes (atomic for threads/shared)
typedef struct {
    uint8_t *base;
    _Atomic size_t current_length;

    // Metadata (not accessed by JIT code directly)
    size_t max_pages;        // 0 or -1 semantics handled by runtime
    int is_memory64;
    int page_size_log2;

    // Guarded allocation info (memory32, reserved mapping)
    void *alloc_base;
    size_t alloc_size;
    size_t guard_start;      // start of PROT_NONE region in bytes
    int is_guarded;
    int is_shared;
} wasmoon_memory_t;

// VMContext v3 - layout MUST match vcode/abi/abi.mbt constants:
//   +0:  memory0 (wasmoon_memory_t*) - High frequency: memory definition pointer (memory 0 fast path)
//   +8:  func_table (void**)         - High frequency: function pointer array
//   +24: table0_base (void**)       - High frequency: table 0 base (fast path for call_indirect)
//   +32: table0_elements (size_t)   - Medium frequency: table 0 element count
//   +40: globals (void*)            - Medium frequency: global variable array
//   +48: tables (void***)           - Low frequency: multi-table pointer array
//   +56: table_count (int)          - Low frequency: number of tables
//   +60: func_count (int)           - Low frequency: number of functions
//   +64: table_sizes (size_t*)      - Low frequency: array of table sizes
//   +72: table_max_sizes (size_t*)  - Low frequency: array of table max sizes
//   +80: memories (uint8_t**)       - Low frequency: multi-memory pointer array
//   +88: memory_sizes (size_t*)     - Low frequency: array of memory sizes
//   +96: memory_max_sizes (size_t*) - Low frequency: array of memory max sizes (in pages)
//   +104: memory_count (int)        - Low frequency: number of memories
typedef struct {
    // High frequency fields (accessed in hot paths)
    wasmoon_memory_t *memory0; // +0:  WebAssembly memory 0 definition
    void **func_table;         // +8:  Array of function pointers
    void **table0_base;        // +16: Table 0 base (for fast call_indirect)

    // Medium frequency fields
    size_t table0_elements;    // +24: Number of elements in table 0
    void *globals;             // +32: Array of global variable values (WasmValue*)

    // Low frequency fields (multi-table support)
    void ***tables;            // +40: Array of table pointers (for table_idx != 0)
    int table_count;           // +48: Number of tables
    int func_count;            // +52: Number of entries in func_table
    size_t *table_sizes;       // +56: Array of table current sizes for all tables
    size_t *table_max_sizes;   // +64: Array of table max sizes (-1 = unlimited)

    // Multi-memory support
    wasmoon_memory_t **memories; // +72: Array of memory definition pointers
    int memory_count;            // +80: Number of memories

    // Debug: current wasm function index (best-effort)
    int32_t debug_current_func_idx; // +84: Currently executing wasm func_idx (-1 = unknown)

    // GC heap for inline allocation (accessed by JIT code)
    uint8_t *gc_heap_ptr;     // +88: Current allocation pointer (aligned to 8)
    uint8_t *gc_heap_limit;   // +96: Allocation limit (triggers slow path when exceeded)
    void *gc_heap;            // +104: GcHeap* pointer for slow path

    // Additional fields (not accessed by JIT code directly)
    int owns_memory0;         // Whether this context owns memory0 (should free it)
    int owns_indirect_table;  // Whether this context owns table0_base (should free it)
    char **args;              // WASI: command line arguments
    int argc;                 // WASI: number of arguments
    char **envp;              // WASI: environment variables
    int envc;                 // WASI: number of env vars
    int wasi_exited;          // WASI: proc_exit called
    int wasi_exit_code;       // WASI: exit code

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

    // Independent WASM stack (separate from host stack)
    // This provides controlled stack overflow behavior and prevents
    // blowing up the host stack from deeply recursive WASM code.
    void *wasm_stack_base;        // Base of allocated region (low address, includes guard page)
    void *wasm_stack_top;         // Top of usable stack (high address, SP starts here)
    size_t wasm_stack_size;       // Total allocated size including guard page
    void *wasm_stack_guard;       // Guard page address (low end, triggers SIGSEGV on overflow)
    size_t guard_page_size;       // Size of guard page (typically one page)

    // WASI file descriptor table
    // fd 0-2 are stdin/stdout/stderr (mapped to native 0-2)
    // fd 3+ are preopened directories and opened files
    int *fd_table;                // Maps WASI fd -> native fd (-1 = not open)
    int fd_table_size;            // Size of fd_table
    int fd_next;                  // Next available fd slot

    // Preopened directories
    char **preopen_paths;         // Host paths for preopened dirs
    char **preopen_guest_paths;   // Guest paths for preopened dirs
    int preopen_count;            // Number of preopened dirs
    int preopen_base_fd;          // First preopen fd (typically 3)

    // WASI stdio buffers for custom callbacks
    int wasi_stdin_use_buffer;    // Whether stdin reads from buffer
    uint8_t *wasi_stdin_buf;      // Buffered stdin data
    size_t wasi_stdin_len;        // Total stdin buffer length
    size_t wasi_stdin_offset;     // Current read offset

    int wasi_stdout_capture;      // Capture stdout writes
    uint8_t *wasi_stdout_buf;     // Captured stdout data
    size_t wasi_stdout_len;       // Captured stdout length
    size_t wasi_stdout_cap;       // Captured stdout capacity

    int wasi_stderr_capture;      // Capture stderr writes
    uint8_t *wasi_stderr_buf;     // Captured stderr data
    size_t wasi_stderr_len;       // Captured stderr length
    size_t wasi_stderr_cap;       // Captured stderr capacity

    // WASI open fd metadata (host path + directory flag)
    char **fd_host_paths;         // Host paths for open fds (owned strings)
    uint8_t *fd_is_dir;           // 1 if fd is a directory

    // WASI stdin callback (MoonBit closure)
    void *wasi_stdin_callback;        // Function pointer for stdin callback
    void *wasi_stdin_callback_data;   // Closure data for stdin callback
} jit_context_t;

// ============ Executable Memory Functions ============
// Forward declarations for GC-managed ExecCode

int64_t wasmoon_jit_alloc_exec(int size);
int wasmoon_jit_copy_code(int64_t dest, uint8_t *src, int size);
static int wasmoon_jit_free_exec(int64_t ptr);

// ============ WASM Stack Functions ============
// Allocate/free independent WASM stack with guard page

int wasmoon_jit_alloc_wasm_stack(int64_t ctx_ptr, int64_t stack_size);
void wasmoon_jit_free_wasm_stack(int64_t ctx_ptr);
int64_t wasmoon_jit_get_wasm_stack_top(int64_t ctx_ptr);

// Call trampoline with stack switching
// Switches to WASM stack before calling, restores host stack after
int wasmoon_jit_call_with_stack_switch(
    int64_t trampoline_ptr,
    int64_t ctx_ptr,
    int64_t func_ptr,
    int64_t *values_vec,
    int values_len
);

#endif // JIT_FFI_H
