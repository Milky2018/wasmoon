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

// GC safepoint metadata table (owned by compiler/runtime, borrowed by context).
typedef struct wasmoon_gc_safepoint_table {
    const uint8_t *stackmap_blob;
    uint32_t stackmap_blob_size;
    const uint32_t *code_offsets;
    uint32_t safepoint_count;
} wasmoon_gc_safepoint_table_t;

// Per-call frame node for GC bookkeeping.
typedef struct wasmoon_gc_frame {
    struct wasmoon_gc_frame *prev;
    uintptr_t frame_id;
    const wasmoon_gc_safepoint_table_t *table;
} wasmoon_gc_frame_t;

// Heap-owned copy of caller roots that must survive a nested JIT/runtime call.
typedef struct wasmoon_gc_root_scope {
    struct wasmoon_gc_root_scope *prev;
    int64_t *roots;
    int32_t root_count;
} wasmoon_gc_root_scope_t;

// VMContext v3 - layout MUST match vcode/abi/abi.mbt constants:
//   +0:   memory0 (wasmoon_memory_t*)  - memory 0 descriptor pointer
//   +8:   memory0_base (uint8_t*)      - cached memory 0 base pointer (hot)
//   +16:  memory0_size (size_t)        - cached memory 0 current length bytes (hot)
//   +24:  func_table (void**)          - function pointer array
//   +32:  table0_base (void**)         - table 0 base (fast path for call_indirect)
//   +40:  table0_elements (size_t)     - table 0 element count
//   +48:  globals (void*)              - global variable array
//   +56:  tables (void***)             - multi-table pointer array
//   +64:  table_count (int)            - number of tables
//   +68:  func_count (int)             - number of functions
//   +72:  table_sizes (size_t*)        - array of table sizes
//   +80:  table_max_sizes (size_t*)    - array of table max sizes
//   +88:  memories (wasmoon_memory_t**) - multi-memory pointer array
//   +96:  memory_count (int)           - number of memories
//   +100: debug_current_func_idx (int32) - current executing func idx
//   +104: gc_heap_ptr (uint8_t*)       - GC inline-allocation cursor
//   +112: gc_heap_limit (uint8_t*)     - GC inline-allocation limit
//   +120: gc_heap (void*)              - GcHeap* pointer
typedef struct {
    // High frequency fields (accessed in hot paths)
    wasmoon_memory_t *memory0;     // +0:  WebAssembly memory 0 descriptor
    uint8_t *memory0_base;         // +8:  Cached memory0->base
    _Atomic size_t memory0_size;   // +16: Cached memory0->current_length
    void **func_table;             // +24: Array of function pointers
    void **table0_base;            // +32: Table 0 base (for fast call_indirect)

    // Medium frequency fields
    size_t table0_elements;    // +40: Number of elements in table 0
    void *globals;             // +48: Array of global variable values (WasmValue*)

    // Low frequency fields (multi-table support)
    void ***tables;            // +56: Array of table pointers (for table_idx != 0)
    int table_count;           // +64: Number of tables
    int func_count;            // +68: Number of entries in func_table
    size_t *table_sizes;       // +72: Array of table current sizes for all tables
    size_t *table_max_sizes;   // +80: Array of table max sizes (-1 = unlimited)

    // Multi-memory support
    wasmoon_memory_t **memories; // +88: Array of memory definition pointers
    int memory_count;            // +96: Number of memories

    // Debug: current wasm function index (best-effort)
    int32_t debug_current_func_idx; // +100: Currently executing wasm func_idx (-1 = unknown)

    // GC heap for inline allocation (accessed by JIT code)
    uint8_t *gc_heap_ptr;     // +104: Current allocation pointer (aligned to 8)
    uint8_t *gc_heap_limit;   // +112: Allocation limit (triggers slow path when exceeded)
    void *gc_heap;            // +120: GcHeap* pointer for slow path

    // GC runtime caches (context-local, not accessed by JIT code directly)
    int32_t *gc_type_cache;
    int gc_num_types;
    int32_t *gc_canonical_indices;
    int gc_num_canonical;
    int32_t *gc_func_type_indices;
    int gc_num_funcs;
    void **gc_func_table;
    int gc_func_table_size;

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

    // WASI file descriptor table (all descriptors, including stdio mappings).
    int *fd_table;                // Maps WASI fd -> native fd (-1 = not open)
    int fd_table_size;            // Size of fd_table
    int fd_next;                  // Next available fd slot

    // WASI stdio descriptor routing (fd_renumber can move these to arbitrary fds)
    int stdin_fd;                 // Descriptor currently bound to stdin stream
    int stdout_fd;                // Descriptor currently bound to stdout stream
    int stderr_fd;                // Descriptor currently bound to stderr stream

    // Preopened directories
    char **preopen_paths;         // Host paths for preopened dirs
    char **preopen_guest_paths;   // Guest paths for preopened dirs
    int *preopen_fds;             // WASI descriptor for each preopen entry
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
    uint64_t *fd_rights_base;     // Effective Preview1 base rights
    uint64_t *fd_rights_inheriting; // Effective Preview1 inheriting rights

    // WASI stdin callback (MoonBit closure)
    void *wasi_stdin_callback;        // Function pointer for stdin callback
    void *wasi_stdin_callback_data;   // Closure data for stdin callback

    // Hostcall callback (MoonBit closure) for JIT -> host function bridging.
    // This is invoked by `wasmoon_jit_hostcall` during JIT execution.
    void *hostcall_callback;          // Function pointer for hostcall callback
    void *hostcall_callback_data;     // Closure data for hostcall callback

    // Invocation-local cooperative cancellation callback. Generated code only
    // passes the context to a C helper; these fields stay outside the fixed ABI.
    void *cancellation_callback;
    void *cancellation_callback_data;

    // ============ Bulk Memory/Table Segment State ============
    // Per-instance (per jit_context_t) storage for bulk memory/table operations:
    //   memory.init/data.drop/table.init/elem.drop and GC array.*_{data,elem}.
    //
    // This is intentionally *not* in the fixed-offset hot VMContext prefix since
    // JIT-generated code never accesses these fields directly; only libcalls do.

    // Data segments (malloc-owned byte copies).
    uint8_t **data_segments;
    size_t *data_segment_sizes;   // number of bytes per segment
    uint8_t *data_dropped;        // 0/1 per segment
    int data_segment_count;

    // Element segments (malloc-owned Int64 copies).
    // Each element segment stores pairs: (value, type_idx) for each element.
    int64_t **elem_segments;
    size_t *elem_segment_sizes;   // number of elements (not Int64 slots)
    uint8_t *elem_dropped;        // 0/1 per segment
    int elem_segment_count;

    // GC safepoint/collection bookkeeping (appended to preserve existing
    // VMContext offsets used by JIT-generated code).
    int gc_collect_requested;
    int gc_in_collect;
    int64_t *gc_root_scratch;
    int32_t gc_root_scratch_len;
    int32_t gc_root_scratch_cap;
    const wasmoon_gc_safepoint_table_t *gc_safepoint_table;
    wasmoon_gc_frame_t *gc_frame_chain_head;
    wasmoon_gc_root_scope_t *gc_root_scope_head;
    // Per-function safepoint tables owned by this context.
    wasmoon_gc_safepoint_table_t *gc_func_safepoint_tables;
    uint8_t **gc_func_stackmap_blobs;
    uint32_t **gc_func_safepoint_offsets;
    int32_t gc_func_safepoint_table_count;
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
