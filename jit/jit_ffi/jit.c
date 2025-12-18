// Copyright 2025
// JIT runtime FFI implementation
// Provides executable memory allocation and function invocation

#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <time.h>
#include <signal.h>
#include <setjmp.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#include <sys/time.h>
#include <unistd.h>
#ifdef __APPLE__
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#endif
#endif

#include "moonbit.h"
#include "jit_ffi.h"

// ============ Trap Handling ============
// Jump buffer for catching JIT traps (BRK instructions and stack overflow)
// Using sigjmp_buf/sigsetjmp/siglongjmp for proper signal handler support
sigjmp_buf g_trap_jmp_buf;
volatile sig_atomic_t g_trap_code = 0;
volatile sig_atomic_t g_trap_active = 0;

// Trap codes:
// 0 = no trap
// 1 = out of bounds memory access
// 2 = call stack exhausted

// Alternate signal stack for handling stack overflow
#define SIGSTACK_SIZE (64 * 1024)  // 64KB alternate stack
static char g_sigstack[SIGSTACK_SIZE];
static int g_sigstack_installed = 0;

// Stack bounds for overflow detection
static void *g_stack_base = NULL;   // Stack base (high address on most platforms)
static size_t g_stack_size = 0;     // Stack size

// Initialize stack bounds
static void init_stack_bounds(void) {
    if (g_stack_base != NULL) return;  // Already initialized

#if defined(__APPLE__)
    // macOS: use pthread_get_stackaddr_np and pthread_get_stacksize_np
    pthread_t self = pthread_self();
    g_stack_base = pthread_get_stackaddr_np(self);
    g_stack_size = pthread_get_stacksize_np(self);
#elif defined(__linux__)
    // Linux: use pthread_attr_getstack
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_getattr_np(pthread_self(), &attr);
    void *stack_addr;
    size_t stack_size;
    pthread_attr_getstack(&attr, &stack_addr, &stack_size);
    // On Linux, stack_addr is the low address
    g_stack_base = (char*)stack_addr + stack_size;
    g_stack_size = stack_size;
    pthread_attr_destroy(&attr);
#else
    // Fallback: estimate from current stack pointer
    volatile int dummy;
    g_stack_base = (void*)&dummy;
    g_stack_size = 8 * 1024 * 1024;  // Assume 8MB stack
#endif
}

// Check if address is near stack boundary (likely stack overflow)
static int is_stack_overflow(void *fault_addr) {
    if (g_stack_base == NULL || g_stack_size == 0) {
        return 0;  // Can't determine
    }

    // Stack grows down: check if fault address is below stack base
    // and within a reasonable range (stack region + guard pages)
    uintptr_t base = (uintptr_t)g_stack_base;
    uintptr_t addr = (uintptr_t)fault_addr;
    uintptr_t stack_low = base - g_stack_size;

    // Consider addresses within stack region or slightly below (guard page)
    // Guard page is typically 4KB-64KB below stack limit
    size_t guard_zone = 64 * 1024;  // 64KB guard zone
    if (stack_low > guard_zone) {
        stack_low -= guard_zone;
    } else {
        stack_low = 0;
    }

    return (addr >= stack_low && addr < base);
}

// Install alternate signal stack for stack overflow handling
static void install_alt_stack(void) {
    if (g_sigstack_installed) return;

    stack_t ss;
    ss.ss_sp = g_sigstack;
    ss.ss_size = SIGSTACK_SIZE;
    ss.ss_flags = 0;
    if (sigaltstack(&ss, NULL) == 0) {
        g_sigstack_installed = 1;
    }
}

// Signal handler for SIGTRAP (triggered by BRK instruction)
static void trap_signal_handler(int sig) {
    (void)sig;
    if (g_trap_active) {
        g_trap_code = 1;  // Out of bounds memory access
        siglongjmp(g_trap_jmp_buf, 1);
    }
}

// Signal handler for SIGSEGV (triggered by stack overflow or invalid memory access)
static void segv_signal_handler(int sig, siginfo_t *info, void *ucontext) {
    (void)sig;
    (void)ucontext;

    if (g_trap_active) {
        void *fault_addr = info->si_addr;

        if (is_stack_overflow(fault_addr)) {
            // Stack overflow detected
            g_trap_code = 2;  // call stack exhausted
            siglongjmp(g_trap_jmp_buf, 1);
        } else {
            // Could be WASM memory access violation
            // For now, treat as out of bounds
            g_trap_code = 1;
            siglongjmp(g_trap_jmp_buf, 1);
        }
    }

    // Not in JIT context, re-raise signal for default handling
    signal(SIGSEGV, SIG_DFL);
    raise(SIGSEGV);
}

// Install trap handler

void install_trap_handler(void) {
    static int installed = 0;
    if (!installed) {
        init_stack_bounds();
        install_alt_stack();  // Must install alternate stack first

        // Install SIGTRAP handler (for BRK instructions)
        struct sigaction sa_trap;
        sa_trap.sa_handler = trap_signal_handler;
        sigemptyset(&sa_trap.sa_mask);
        sa_trap.sa_flags = 0;
        sigaction(SIGTRAP, &sa_trap, NULL);

        // Install SIGSEGV handler (for stack overflow)
        // Use SA_SIGINFO to get fault address, SA_ONSTACK to use alternate stack
        struct sigaction sa_segv;
        sa_segv.sa_sigaction = segv_signal_handler;
        sigemptyset(&sa_segv.sa_mask);
        sa_segv.sa_flags = SA_SIGINFO | SA_ONSTACK;  // Run on alternate stack!
        sigaction(SIGSEGV, &sa_segv, NULL);

        // Also handle SIGBUS (on some platforms, stack overflow triggers SIGBUS)
        sigaction(SIGBUS, &sa_segv, NULL);

        installed = 1;
    }
}

// Check if a trap occurred (returns 0 = no trap, 1 = out of bounds, etc.)
MOONBIT_FFI_EXPORT int wasmoon_jit_get_trap_code(void) {
    return (int)g_trap_code;
}

// Clear trap code
MOONBIT_FFI_EXPORT void wasmoon_jit_clear_trap(void) {
    g_trap_code = 0;
}

// Allocate a JIT context v3
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_alloc_context(int func_count) {
    jit_context_t *ctx = (jit_context_t *)malloc(sizeof(jit_context_t));
    if (!ctx) return 0;

    // Initialize all fields to match VMContext v3 layout
    // High frequency fields
    ctx->memory_base = NULL;
    ctx->memory_size = 0;
    ctx->func_table = (void **)calloc(func_count, sizeof(void *));
    if (!ctx->func_table) {
        free(ctx);
        return 0;
    }
    ctx->table0_base = NULL;      // Table 0 base (fast path for call_indirect)

    // Medium frequency fields
    ctx->table0_elements = 0;     // Table 0 element count
    ctx->globals = NULL;

    // Low frequency fields (multi-table support)
    ctx->tables = NULL;           // Array of table pointers (for table_idx != 0)
    ctx->table_count = 0;
    ctx->func_count = func_count;

    // Additional fields (not accessed by JIT code directly)
    ctx->owns_indirect_table = 0; // Default: does not own table0_base
    ctx->args = NULL;
    ctx->argc = 0;
    ctx->envp = NULL;
    ctx->envc = 0;

    return (int64_t)ctx;
}

// Set a function pointer in context v2
MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_func(int64_t ctx_ptr, int idx, int64_t func_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx && idx >= 0 && idx < ctx->func_count) {
        ctx->func_table[idx] = (void *)func_ptr;
    }
}

// Set memory in context v2
MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_memory(int64_t ctx_ptr, int64_t mem_ptr, int64_t mem_size) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx) {
        ctx->memory_base = (uint8_t *)mem_ptr;
        ctx->memory_size = (size_t)mem_size;
    }
}

// Set globals array in context v2
MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_globals(int64_t ctx_ptr, int64_t globals_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx) {
        ctx->globals = (void *)globals_ptr;
    }
}

// Get function table base from context v2
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_get_func_table(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    return ctx ? (int64_t)ctx->func_table : 0;
}

// Allocate indirect table for context v3
// Each entry is 16 bytes: (func_ptr, type_idx) pair
// Layout: [func_ptr_0, type_idx_0, func_ptr_1, type_idx_1, ...]
MOONBIT_FFI_EXPORT int wasmoon_jit_ctx_alloc_indirect_table(int64_t ctx_ptr, int count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || count <= 0) return 0;

    // Only free if we own the current table0_base
    if (ctx->table0_base && ctx->owns_indirect_table) {
        free(ctx->table0_base);
    }

    // Allocate 2 slots per entry: func_ptr and type_idx
    // Initialize to 0 (NULL func_ptr, type -1 would indicate uninitialized but we use 0)
    ctx->table0_base = (void **)calloc(count * 2, sizeof(void *));
    if (!ctx->table0_base) {
        ctx->table0_elements = 0;
        ctx->owns_indirect_table = 0;
        return 0;
    }
    // Initialize type indices to -1 (uninitialized marker)
    for (int i = 0; i < count; i++) {
        ctx->table0_base[i * 2 + 1] = (void*)(intptr_t)(-1);
    }
    ctx->table0_elements = count;
    ctx->owns_indirect_table = 1;  // We own this table
    return 1;
}

// Set indirect table entry in context v3
// Now takes type_idx parameter to store alongside func_ptr
MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_indirect(int64_t ctx_ptr, int table_idx, int func_idx, int type_idx) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx && ctx->table0_base &&
        table_idx >= 0 && (size_t)table_idx < ctx->table0_elements &&
        func_idx >= 0 && func_idx < ctx->func_count) {
        // Store func_ptr at offset 0, type_idx at offset 8
        ctx->table0_base[table_idx * 2] = ctx->func_table[func_idx];
        ctx->table0_base[table_idx * 2 + 1] = (void*)(intptr_t)type_idx;
    }
}

// Get indirect table base from context v3
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_get_indirect_table(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx && ctx->table0_base) {
        return (int64_t)ctx->table0_base;
    }
    return ctx ? (int64_t)ctx->func_table : 0;
}

// Free context v3
// Also frees memory_base and globals (owned by context)
// Note: table0_base is only freed if owns_indirect_table is set
MOONBIT_FFI_EXPORT void wasmoon_jit_free_context(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx) {
        if (ctx->func_table) free(ctx->func_table);
        if (ctx->tables) free(ctx->tables);
        // Only free table0_base if we own it (allocated via alloc_indirect_table)
        // Borrowed tables (from set_table_pointers) are managed by JITTable's GC
        if (ctx->table0_base && ctx->owns_indirect_table) free(ctx->table0_base);
        if (ctx->memory_base) free(ctx->memory_base);
        if (ctx->globals) free(ctx->globals);
        free(ctx);
    }
}

// ============ GC-managed JITContext ============

// Finalize function for GC-managed JITContext
static void finalize_jit_context(void *self) {
    int64_t *ptr = (int64_t *)self;
    if (*ptr != 0) {
        wasmoon_jit_free_context(*ptr);
        *ptr = 0;
    }
}

// Create a GC-managed JIT context
// Returns external object pointer (managed by MoonBit GC)
MOONBIT_FFI_EXPORT void *wasmoon_jit_alloc_context_managed(int func_count) {
    int64_t ctx_ptr = wasmoon_jit_alloc_context(func_count);
    if (ctx_ptr == 0) {
        return NULL;
    }

    // Create GC-managed external object with Int64 payload
    int64_t *payload = (int64_t *)moonbit_make_external_object(finalize_jit_context, sizeof(int64_t));
    if (!payload) {
        wasmoon_jit_free_context(ctx_ptr);
        return NULL;
    }

    *payload = ctx_ptr;
    return payload;
}

// Get the context pointer from a managed JITContext object
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_context_ptr(void *jit_context) {
    if (!jit_context) return 0;
    return *(int64_t *)jit_context;
}

// ============ Shared Indirect Table Support ============

// Allocate a shared indirect table that can be used by multiple JIT modules
// Returns pointer to allocated table, or 0 on failure
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_alloc_shared_indirect_table(int count) {
    if (count <= 0) return 0;

    // Allocate 2 slots per entry: func_ptr and type_idx
    void **table = (void **)calloc(count * 2, sizeof(void *));
    if (!table) return 0;

    // Initialize all entries to -1 (null reference sentinel)
    // func_ptr = -1 represents ref.null (matching IR translator convention)
    // type_idx = -1 represents uninitialized/invalid type
    for (int i = 0; i < count; i++) {
        table[i * 2] = (void*)(intptr_t)(-1);     // func_ptr (null reference)
        table[i * 2 + 1] = (void*)(intptr_t)(-1); // type_idx
    }

    return (int64_t)table;
}

// Free a shared indirect table
MOONBIT_FFI_EXPORT void wasmoon_jit_free_shared_indirect_table(int64_t table_ptr) {
    void **table = (void **)table_ptr;
    if (table) {
        free(table);
    }
}

// Set an entry in a shared indirect table
// table_idx: index in the table
// func_ptr: pointer to the function
// type_idx: type index for type checking
MOONBIT_FFI_EXPORT void wasmoon_jit_shared_table_set(int64_t table_ptr, int table_idx, int64_t func_ptr, int type_idx) {
    void **table = (void **)table_ptr;
    if (table && table_idx >= 0) {
        table[table_idx * 2] = (void *)func_ptr;
        table[table_idx * 2 + 1] = (void*)(intptr_t)type_idx;
    }
}

// Configure a JIT context to use a shared indirect table instead of allocating its own
// This allows multiple modules to share the same table
MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_use_shared_table(int64_t ctx_ptr, int64_t shared_table_ptr, int count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;

    // Free existing table0_base only if we own it
    if (ctx->table0_base && ctx->owns_indirect_table) {
        free(ctx->table0_base);
    }

    // Point to the shared table (borrowed, not owned)
    ctx->table0_base = (void **)shared_table_ptr;
    ctx->table0_elements = count;
    ctx->owns_indirect_table = 0;  // We don't own this table
}

// Configure JIT context with multiple indirect tables (for multi-table support)
// table_ptrs: Array of Int64 (table pointers from Store.jit_tables)
// table_count: Number of tables
// This enables proper multi-table support where each call_indirect can specify which table to use
MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_table_pointers(
    int64_t ctx_ptr,
    int64_t* table_ptrs,
    int table_count
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || table_count <= 0 || !table_ptrs) return;

    // Free existing tables array if any
    if (ctx->tables) {
        free(ctx->tables);
        ctx->tables = NULL;
        ctx->table_count = 0;
    }

    // Allocate array to hold table pointers
    ctx->tables = (void ***)calloc(table_count, sizeof(void **));
    if (!ctx->tables) {
        ctx->table_count = 0;
        return;
    }

    // Copy table pointers (note: tables themselves are owned by Store, we just hold pointers)
    for (int i = 0; i < table_count; i++) {
        ctx->tables[i] = (void **)table_ptrs[i];
    }
    ctx->table_count = table_count;

    // For backward compatibility: if there's at least one table, set it as table0_base
    // Note: This is a borrowed pointer, we don't own it
    if (table_count > 0 && table_ptrs[0] != 0) {
        ctx->table0_base = (void **)table_ptrs[0];
        ctx->owns_indirect_table = 0;  // Borrowed from JITTable, not owned
    }
}


// Global v2 context (for WASI trampolines)

jit_context_t *g_jit_context = NULL;
// Global reference to managed JITContext object (to prevent GC collection)
static void *g_jit_context_obj = NULL;

// Set global v2 context with managed object (handles reference counting)
MOONBIT_FFI_EXPORT void wasmoon_jit_set_context_managed(void *jit_context) {
    // Decref old context object
    if (g_jit_context_obj != NULL) {
        moonbit_decref(g_jit_context_obj);
    }
    // Incref new context object
    if (jit_context != NULL) {
        moonbit_incref(jit_context);
        g_jit_context = (jit_context_t *)(*(int64_t *)jit_context);
    } else {
        g_jit_context = NULL;
    }
    g_jit_context_obj = jit_context;
}

// Get global v2 context
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_context(void) {
    return (int64_t)g_jit_context;
}

// ============ Trampoline-based Call (New, Simple) ============
// Call via a JIT-generated entry trampoline
// The trampoline handles all ABI complexity - no inline assembly here!
//
// Trampoline signature: int trampoline(vmctx, values_vec, func_ptr)
// - vmctx: VMContext pointer
// - values_vec: Array of int64_t for args (in) and results (out)
// - func_ptr: Target WASM function pointer
// Returns: trap code (0 = success)
typedef int (*entry_trampoline_fn)(jit_context_t *vmctx, int64_t *values_vec, void *func_ptr);

MOONBIT_FFI_EXPORT int wasmoon_jit_call_trampoline(
    int64_t trampoline_ptr,
    int64_t ctx_ptr,
    int64_t func_ptr,
    int64_t* values_vec,
    int values_len
) {
    if (!trampoline_ptr || !ctx_ptr || !func_ptr) return -1;

    install_trap_handler();
    g_trap_code = 0;
    g_trap_active = 1;

    // Set global context for WASI trampolines
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    g_jit_context = ctx;

    if (sigsetjmp(g_trap_jmp_buf, 1) != 0) {
        g_trap_active = 0;
        return (int)g_trap_code;
    }

    // Call the JIT-generated trampoline
    // This is a simple C function call - no inline assembly needed!
    entry_trampoline_fn trampoline = (entry_trampoline_fn)trampoline_ptr;
    int result = trampoline(ctx, values_vec, (void *)func_ptr);

    g_trap_active = 0;

    // Check if a trap occurred
    if (g_trap_code != 0) {
        return (int)g_trap_code;
    }

    return result;
}

// ============ Spectest Trampolines ============
// These are no-op functions used by the WebAssembly test suite

// print: () -> ()
static void spectest_print_impl(int64_t func_table, int64_t mem_base) {
    (void)func_table;
    (void)mem_base;
}

// print_i32: (i32) -> ()
static void spectest_print_i32_impl(int64_t func_table, int64_t mem_base, int64_t arg0) {
    (void)func_table;
    (void)mem_base;
    (void)arg0;
}

// print_i64: (i64) -> ()
static void spectest_print_i64_impl(int64_t func_table, int64_t mem_base, int64_t arg0) {
    (void)func_table;
    (void)mem_base;
    (void)arg0;
}

// print_f32: (f32) -> ()
static void spectest_print_f32_impl(int64_t func_table, int64_t mem_base, int64_t arg0) {
    (void)func_table;
    (void)mem_base;
    (void)arg0;
}

// print_f64: (f64) -> ()
static void spectest_print_f64_impl(int64_t func_table, int64_t mem_base, int64_t arg0) {
    (void)func_table;
    (void)mem_base;
    (void)arg0;
}

// print_i32_f32: (i32, f32) -> ()
static void spectest_print_i32_f32_impl(int64_t func_table, int64_t mem_base, int64_t arg0, int64_t arg1) {
    (void)func_table;
    (void)mem_base;
    (void)arg0;
    (void)arg1;
}

// print_f64_f64: (f64, f64) -> ()
static void spectest_print_f64_f64_impl(int64_t func_table, int64_t mem_base, int64_t arg0, int64_t arg1) {
    (void)func_table;
    (void)mem_base;
    (void)arg0;
    (void)arg1;
}

// Get spectest trampoline pointers
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_ptr(void) {
    return (int64_t)spectest_print_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_i32_ptr(void) {
    return (int64_t)spectest_print_i32_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_i64_ptr(void) {
    return (int64_t)spectest_print_i64_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_f32_ptr(void) {
    return (int64_t)spectest_print_f32_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_f64_ptr(void) {
    return (int64_t)spectest_print_f64_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_i32_f32_ptr(void) {
    return (int64_t)spectest_print_i32_f32_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_spectest_print_f64_f64_ptr(void) {
    return (int64_t)spectest_print_f64_f64_impl;
}

// ============ Linear Memory Allocation ============

#define WASM_PAGE_SIZE 65536

// Allocate linear memory for WASM (returns 0 on failure)
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_alloc_memory(int64_t size) {
    if (size <= 0) return 0;
    void *mem = calloc(1, (size_t)size);
    return (int64_t)mem;
}

// Free linear memory
MOONBIT_FFI_EXPORT void wasmoon_jit_free_memory(int64_t mem_ptr) {
    if (mem_ptr) {
        free((void *)mem_ptr);
    }
}

// ============ Memory operations v2 (for new ABI) ============
// These use g_jit_context instead of g_jit_context

// Grow linear memory by delta pages (v2)
MOONBIT_FFI_EXPORT int32_t wasmoon_jit_memory_grow(int32_t delta, int32_t max_pages) {
    if (!g_jit_context) return -1;
    if (delta < 0) return -1;

    size_t current_size = g_jit_context->memory_size;
    int32_t current_pages = (int32_t)(current_size / WASM_PAGE_SIZE);

    // Check for overflow
    int64_t new_pages_64 = (int64_t)current_pages + (int64_t)delta;
    if (new_pages_64 > 65536) return -1;  // Max 4GB (65536 pages)

    // Check against max limit
    int32_t effective_max = (max_pages > 0) ? max_pages : 65536;
    if (new_pages_64 > effective_max) return -1;

    int32_t new_pages = (int32_t)new_pages_64;
    size_t new_size = (size_t)new_pages * WASM_PAGE_SIZE;

    // No change needed if delta is 0
    if (delta == 0) return current_pages;

    // Reallocate memory
    uint8_t *new_mem = (uint8_t *)realloc(g_jit_context->memory_base, new_size);
    if (!new_mem) return -1;

    // Zero-initialize the new pages
    memset(new_mem + current_size, 0, new_size - current_size);

    // Update context
    g_jit_context->memory_base = new_mem;
    g_jit_context->memory_size = new_size;

    return current_pages;
}

// Get current memory size in pages (v2)
MOONBIT_FFI_EXPORT int32_t wasmoon_jit_memory_size(void) {
    if (!g_jit_context) return 0;
    return (int32_t)(g_jit_context->memory_size / WASM_PAGE_SIZE);
}

// Get current memory base (v2)
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_base(void) {
    if (!g_jit_context) return 0;
    return (int64_t)g_jit_context->memory_base;
}

// Get current memory size in bytes (v2)
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_size_bytes(void) {
    if (!g_jit_context) return 0;
    return (int64_t)g_jit_context->memory_size;
}

// Get function pointer for memory_grow v2
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_grow_ptr(void) {
    return (int64_t)wasmoon_jit_memory_grow;
}

// Get function pointer for get_memory_base v2
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_base_ptr(void) {
    return (int64_t)wasmoon_jit_get_memory_base;
}

// Get function pointer for get_memory_size_bytes v2
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_size_bytes_ptr(void) {
    return (int64_t)wasmoon_jit_get_memory_size_bytes;
}

// Get function pointer for memory_size v2
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_size_ptr(void) {
    return (int64_t)wasmoon_jit_memory_size;
}

// Copy data to linear memory at offset
MOONBIT_FFI_EXPORT int wasmoon_jit_memory_init(int64_t mem_ptr, int64_t offset, moonbit_bytes_t data, int size) {
    if (!mem_ptr || !data || size <= 0) return -1;
    uint8_t *mem = (uint8_t *)mem_ptr;
    memcpy(mem + offset, data, (size_t)size);
    return 0;
}

// Get memory base from context
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_get_memory(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx) {
        return (int64_t)ctx->memory_base;
    }
    return 0;
}

// ============ Multi-value return support ============

// The new v3 ABI uses wasmoon_jit_call with X0=callee_vmctx, X1=caller_vmctx

// ============ Executable memory management ============

// Executable memory block
typedef struct {
    void *code;
    size_t size;
} jit_code_block_t;

// ============ GC-managed ExecCode ============

// Finalize function for ExecCode - releases the executable memory
// NOTE: This is called by MoonBit GC when the object becomes unreachable
// The finalize function MUST NOT free the container itself (GC does that)
static void finalize_exec_code(void *self) {
    int64_t *ptr = (int64_t *)self;
    if (*ptr != 0) {
        wasmoon_jit_free_exec(*ptr);
        *ptr = 0;
    }
}

// Create a GC-managed executable code object
// Returns external object pointer (managed by MoonBit GC)
MOONBIT_FFI_EXPORT void *wasmoon_jit_alloc_exec_managed(moonbit_bytes_t code, int size) {
    if (size <= 0 || !code) {
        return NULL;
    }

    // Allocate executable memory
    int64_t ptr = wasmoon_jit_alloc_exec(size);
    if (ptr == 0) {
        return NULL;
    }

    // Copy code to executable memory
    int result = wasmoon_jit_copy_code(ptr, code, size);
    if (result != 0) {
        wasmoon_jit_free_exec(ptr);
        return NULL;
    }

    // Create GC-managed external object with Int64 payload
    int64_t *payload = (int64_t *)moonbit_make_external_object(finalize_exec_code, sizeof(int64_t));
    if (!payload) {
        wasmoon_jit_free_exec(ptr);
        return NULL;
    }

    *payload = ptr;
    return payload;
}

// Get the executable pointer from a managed ExecCode object
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_exec_code_ptr(void *exec_code) {
    if (!exec_code) return 0;
    return *(int64_t *)exec_code;
}

// Maximum number of allocated code blocks (simple implementation)
#define MAX_CODE_BLOCKS 1024
static jit_code_block_t code_blocks[MAX_CODE_BLOCKS];
static int num_code_blocks = 0;

// Get page size
static size_t get_page_size(void) {
#ifdef _WIN32
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return si.dwPageSize;
#else
    return (size_t)sysconf(_SC_PAGESIZE);
#endif
}

// Round up to page size
static size_t round_up_to_page(size_t size) {
    size_t page_size = get_page_size();
    return (size + page_size - 1) & ~(page_size - 1);
}

// Allocate executable memory
// Returns pointer to allocated memory as int64_t (0 on failure)
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_alloc_exec(int size) {
    if (size <= 0 || num_code_blocks >= MAX_CODE_BLOCKS) {
        return 0;
    }

    size_t alloc_size = round_up_to_page((size_t)size);

#ifdef _WIN32
    void *ptr = VirtualAlloc(NULL, alloc_size, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
#else
    // Allocate with WRITE permission first, will change to EXEC after copying
    void *ptr = mmap(NULL, alloc_size, PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (ptr == MAP_FAILED) {
        return 0;
    }
#endif

    if (ptr) {
        code_blocks[num_code_blocks].code = ptr;
        code_blocks[num_code_blocks].size = alloc_size;
        num_code_blocks++;
    }

    return (int64_t)ptr;
}

// Copy code to executable memory
MOONBIT_FFI_EXPORT int wasmoon_jit_copy_code(int64_t dest, moonbit_bytes_t src, int size) {
    void *ptr = (void *)dest;
    if (!ptr || !src || size <= 0) {
        return -1;
    }

    // Copy code
    memcpy(ptr, src, (size_t)size);

    // Find the code block to get the size for mprotect
    size_t alloc_size = 0;
    for (int i = 0; i < num_code_blocks; i++) {
        if (code_blocks[i].code == ptr) {
            alloc_size = code_blocks[i].size;
            break;
        }
    }
    if (alloc_size == 0) {
        return -1;
    }

#ifndef _WIN32
    // Change permissions from WRITE to EXEC
    if (mprotect(ptr, alloc_size, PROT_READ | PROT_EXEC) != 0) {
        return -1;
    }
#endif

    // Flush instruction cache
#ifdef __APPLE__
    sys_icache_invalidate(ptr, (size_t)size);
#elif defined(__aarch64__) && !defined(_WIN32)
    __builtin___clear_cache(ptr, (char*)ptr + size);
#endif

    return 0;
}

// ============ Bulk Memory Operations ============

// memory.fill: Fill memory region with a byte value
// Parameters: dst (offset), val (byte value), size (count)
// Traps if: dst + size > memory_size (out of bounds)
MOONBIT_FFI_EXPORT void wasmoon_jit_memory_fill(int32_t dst, int32_t val, int32_t size) {
    jit_context_t *ctx = g_jit_context;
    if (!ctx || !ctx->memory_base) {
        g_trap_code = 1;  // Out of bounds memory access
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Check bounds
    if (dst < 0 || size < 0 || (uint32_t)dst + (uint32_t)size > ctx->memory_size) {
        g_trap_code = 1;  // Out of bounds memory access
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Fill memory with byte value (val & 0xFF)
    memset(ctx->memory_base + dst, val & 0xFF, size);
}

// memory.copy: Copy memory region
// Parameters: dst (dest offset), src (source offset), size (count)
// Traps if: dst + size > memory_size || src + size > memory_size
// Handles overlapping regions correctly (like memmove)
MOONBIT_FFI_EXPORT void wasmoon_jit_memory_copy(int32_t dst, int32_t src, int32_t size) {
    jit_context_t *ctx = g_jit_context;
    if (!ctx || !ctx->memory_base) {
        g_trap_code = 1;  // Out of bounds memory access
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Check bounds for both source and destination
    if (dst < 0 || src < 0 || size < 0 ||
        (uint32_t)dst + (uint32_t)size > ctx->memory_size ||
        (uint32_t)src + (uint32_t)size > ctx->memory_size) {
        g_trap_code = 1;  // Out of bounds memory access
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }

    // Use memmove to handle overlapping regions correctly
    memmove(ctx->memory_base + dst, ctx->memory_base + src, size);
}

// Get function pointer for memory_fill v2
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_fill_ptr(void) {
    return (int64_t)wasmoon_jit_memory_fill;
}

// Get function pointer for memory_copy v2
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_copy_ptr(void) {
    return (int64_t)wasmoon_jit_memory_copy;
}

// Free executable memory
static int wasmoon_jit_free_exec(int64_t ptr_i64) {
    void *ptr = (void *)ptr_i64;
    if (!ptr) {
        return -1;
    }

    // Find the code block
    for (int i = 0; i < num_code_blocks; i++) {
        if (code_blocks[i].code == ptr) {
#ifdef _WIN32
            VirtualFree(ptr, 0, MEM_RELEASE);
#else
            munmap(ptr, code_blocks[i].size);
#endif
            // Remove from array (shift remaining)
            for (int j = i; j < num_code_blocks - 1; j++) {
                code_blocks[j] = code_blocks[j + 1];
            }
            num_code_blocks--;
            return 0;
        }
    }

    return -1;  // Not found
}

// Write an int64 value to a memory address
MOONBIT_FFI_EXPORT void wasmoon_jit_write_i64(int64_t addr, int64_t value) {
    if (addr != 0) {
        *((int64_t*)addr) = value;
    }
}

// Read an int64 value from a memory address
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_read_i64(int64_t addr) {
    if (addr != 0) {
        return *((int64_t*)addr);
    }
    return 0;
}
