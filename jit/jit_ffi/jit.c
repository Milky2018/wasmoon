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
#include "gc_heap.h"

// ============ GC Heap Pointer ============
// Global heap pointer for JIT GC operations
// Set before JIT execution, cleared after
static GcHeap* g_gc_heap = NULL;

// ============ Trap Handling ============
// Jump buffer for catching JIT traps (BRK instructions and stack overflow)
// Using sigjmp_buf/sigsetjmp/siglongjmp for proper signal handler support
sigjmp_buf g_trap_jmp_buf;
volatile sig_atomic_t g_trap_code = 0;
volatile sig_atomic_t g_trap_active = 0;

// Trap codes (matching WebAssembly trap types):
// 0 = no trap
// 1 = out of bounds memory access
// 2 = call stack exhausted
// 3 = unreachable executed
// 4 = indirect call type mismatch
// 5 = invalid conversion to integer
// 6 = integer divide by zero
// 7 = integer overflow
// 99 = unknown trap
//
// BRK immediate mapping (from codegen):
// BRK #0 -> unreachable (trap code 3)
// BRK #2 -> type mismatch (trap code 4)
// BRK #3 -> invalid conversion (trap code 5)
// BRK #4 -> divide by zero (trap code 6)
// BRK #5 -> integer overflow (trap code 7)

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
// Uses SA_SIGINFO to get ucontext and extract BRK immediate
static void trap_signal_handler(int sig, siginfo_t *info, void *ucontext) {
    (void)sig;
    (void)info;

    if (g_trap_active) {
        int trap_code = 99;  // Default to unknown

#if defined(__APPLE__) && defined(__aarch64__)
        // On macOS ARM64, extract PC from ucontext and read BRK immediate
        ucontext_t *uc = (ucontext_t *)ucontext;
        uint64_t pc = uc->uc_mcontext->__ss.__pc;
        // PC points to the instruction after BRK, so read at PC-4
        uint32_t instr = *(uint32_t *)(pc - 4);
        // BRK encoding: 0xD4200000 | (imm16 << 5)
        // Extract imm16: (instr >> 5) & 0xFFFF
        int brk_imm = (instr >> 5) & 0xFFFF;

        // Map BRK immediate to trap code
        switch (brk_imm) {
            case 0: trap_code = 3; break;   // unreachable
            case 1: trap_code = 1; break;   // out of bounds (memory/table access)
            case 2: trap_code = 4; break;   // indirect call type mismatch
            case 3: trap_code = 5; break;   // invalid conversion to integer
            case 4: trap_code = 6; break;   // integer divide by zero
            case 5: trap_code = 7; break;   // integer overflow
            default: trap_code = 99; break; // unknown
        }
#elif defined(__linux__) && defined(__aarch64__)
        // On Linux ARM64
        ucontext_t *uc = (ucontext_t *)ucontext;
        uint64_t pc = uc->uc_mcontext.pc;
        uint32_t instr = *(uint32_t *)(pc - 4);
        int brk_imm = (instr >> 5) & 0xFFFF;

        switch (brk_imm) {
            case 0: trap_code = 3; break;   // unreachable
            case 1: trap_code = 1; break;   // out of bounds (memory/table access)
            case 2: trap_code = 4; break;   // indirect call type mismatch
            case 3: trap_code = 5; break;   // invalid conversion to integer
            case 4: trap_code = 6; break;   // integer divide by zero
            case 5: trap_code = 7; break;   // integer overflow
            default: trap_code = 99; break; // unknown
        }
#else
        (void)ucontext;
        trap_code = 99;  // Unknown on unsupported platforms
#endif

        g_trap_code = trap_code;
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
            // Could be WASM memory access violation or other error
            // Use unknown trap code since we can't determine the exact cause
            g_trap_code = 99;
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
        // Use SA_SIGINFO to get ucontext for extracting BRK immediate
        struct sigaction sa_trap;
        sa_trap.sa_sigaction = trap_signal_handler;
        sigemptyset(&sa_trap.sa_mask);
        sa_trap.sa_flags = SA_SIGINFO;
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
    ctx->table_sizes = NULL;      // Array of table sizes
    ctx->table_max_sizes = NULL;  // Array of table max sizes

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
        if (ctx->table_sizes) free(ctx->table_sizes);
        if (ctx->table_max_sizes) free(ctx->table_max_sizes);
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

// Grow a table by delta elements, initializing new elements with init_value
// Returns previous size on success, or -1 on failure
// Following Cranelift's table_grow_func_ref pattern
MOONBIT_FFI_EXPORT int32_t wasmoon_jit_table_grow(
    int32_t table_idx,
    int64_t delta,
    int64_t init_value
) {
    jit_context_t *ctx = g_jit_context;
    if (!ctx || table_idx < 0 || delta < 0) return -1;
    if (table_idx >= ctx->table_count) return -1;
    if (!ctx->tables || !ctx->table_sizes) return -1;

    size_t old_size = ctx->table_sizes[table_idx];
    size_t new_size = old_size + (size_t)delta;

    // Check for overflow
    if (new_size < old_size) return -1;

    // Check against max size limit (following Cranelift pattern)
    if (ctx->table_max_sizes) {
        size_t max_size = ctx->table_max_sizes[table_idx];
        if (new_size > max_size) return -1;
    }

    // Get the old table pointer
    void **old_table = ctx->tables[table_idx];

    // Allocate new table (2 slots per entry: func_ptr and type_idx)
    void **new_table = (void **)calloc(new_size * 2, sizeof(void *));
    if (!new_table) return -1;

    // Copy existing elements
    if (old_table && old_size > 0) {
        memcpy(new_table, old_table, old_size * 2 * sizeof(void *));
    }

    // Initialize new elements with init_value
    // For funcref: init_value is the function pointer (or -1 for null)
    // type_idx is set to -1 (unknown) for grown elements
    for (size_t i = old_size; i < new_size; i++) {
        new_table[i * 2] = (void *)init_value;      // func_ptr
        new_table[i * 2 + 1] = (void*)(intptr_t)(-1); // type_idx (unknown)
    }

    // Update the tables array
    ctx->tables[table_idx] = new_table;
    ctx->table_sizes[table_idx] = new_size;

    // Update table0 fast path if this is table 0
    if (table_idx == 0) {
        ctx->table0_base = new_table;
        ctx->table0_elements = new_size;
    }

    // Free old table
    if (old_table) {
        free(old_table);
    }

    return (int32_t)old_size;
}

// Get table_grow function pointer for JIT
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_table_grow_ptr(void) {
    return (int64_t)wasmoon_jit_table_grow;
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
// table_sizes: Array of Int (table sizes for bounds checking)
// table_max_sizes: Array of Int (max sizes, -1 = unlimited)
// table_count: Number of tables
// This enables proper multi-table support where each call_indirect can specify which table to use
MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_table_pointers(
    int64_t ctx_ptr,
    int64_t* table_ptrs,
    int32_t* table_sizes,
    int32_t* table_max_sizes,
    int table_count
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || table_count <= 0 || !table_ptrs) return;

    // Free existing tables array if any
    if (ctx->tables) {
        free(ctx->tables);
        ctx->tables = NULL;
    }
    // Free existing table_sizes array if any
    if (ctx->table_sizes) {
        free(ctx->table_sizes);
        ctx->table_sizes = NULL;
    }
    // Free existing table_max_sizes array if any
    if (ctx->table_max_sizes) {
        free(ctx->table_max_sizes);
        ctx->table_max_sizes = NULL;
    }
    ctx->table_count = 0;

    // Allocate array to hold table pointers
    ctx->tables = (void ***)calloc(table_count, sizeof(void **));
    if (!ctx->tables) {
        return;
    }

    // Allocate array to hold table sizes
    ctx->table_sizes = (size_t *)calloc(table_count, sizeof(size_t));
    if (!ctx->table_sizes) {
        free(ctx->tables);
        ctx->tables = NULL;
        return;
    }

    // Allocate array to hold table max sizes
    ctx->table_max_sizes = (size_t *)calloc(table_count, sizeof(size_t));
    if (!ctx->table_max_sizes) {
        free(ctx->tables);
        free(ctx->table_sizes);
        ctx->tables = NULL;
        ctx->table_sizes = NULL;
        return;
    }

    // Copy table pointers, sizes, and max sizes
    for (int i = 0; i < table_count; i++) {
        ctx->tables[i] = (void **)table_ptrs[i];
        if (table_sizes) {
            ctx->table_sizes[i] = (size_t)table_sizes[i];
        }
        if (table_max_sizes) {
            // -1 means unlimited, store as SIZE_MAX
            ctx->table_max_sizes[i] = (table_max_sizes[i] < 0) ? SIZE_MAX : (size_t)table_max_sizes[i];
        } else {
            ctx->table_max_sizes[i] = SIZE_MAX;  // Default: unlimited
        }
    }
    ctx->table_count = table_count;

    // For backward compatibility: if there's at least one table, set it as table0_base
    // Note: This is a borrowed pointer, we don't own it
    if (table_count > 0 && table_ptrs[0] != 0) {
        ctx->table0_base = (void **)table_ptrs[0];
        ctx->owns_indirect_table = 0;  // Borrowed from JITTable, not owned
        // Set table0_elements for bounds checking
        if (table_sizes) {
            ctx->table0_elements = table_sizes[0];
        }
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

// ============ GC Runtime Helpers ============
// These helpers support GC operations in JIT code.
// They access global type cache set up before JIT execution.

// GC type cache
// Format: [super_idx, kind, num_fields] per type (3 int32_t each)
static int32_t *g_gc_type_cache = NULL;
static int g_gc_num_types = 0;
static int32_t *g_gc_canonical_indices = NULL;
static int g_gc_num_canonical = 0;

// Type kind constants
#define GC_KIND_FUNC   0
#define GC_KIND_STRUCT 1
#define GC_KIND_ARRAY  2

// Value encoding helpers
// null: 0
// i31: (value << 1) | 1 (positive, lowest bit = 1)
// struct/array ref: gc_ref << 1 (positive, lowest bit = 0, gc_ref >= 1, so value >= 2)
// funcref: -(func_idx + 1) for IR, or func_ptr | FUNCREF_TAG for table entries
// externref: 0x4000000000000000 | (host_idx << 1) (bit 62 set)

#define EXTERNREF_TAG 0x4000000000000000LL
#define FUNCREF_TAG   0x2000000000000000LL  // Bit 61 for table funcref pointers
#define REF_TAGS_MASK (EXTERNREF_TAG | FUNCREF_TAG)

static inline int is_null_value(int64_t val) {
    return val == 0;
}

static inline int is_externref_value(int64_t val) {
    return (val & EXTERNREF_TAG) != 0;  // Bit 62 set
}

static inline int is_funcref_ptr_value(int64_t val) {
    return (val & FUNCREF_TAG) != 0 && (val & EXTERNREF_TAG) == 0;  // Bit 61 set, bit 62 clear
}

static inline int is_funcref_value(int64_t val) {
    // Either negative (IR encoded) or tagged pointer (table entry)
    return val < 0 || is_funcref_ptr_value(val);
}

static inline int is_i31_value(int64_t val) {
    return val > 0 && (val & REF_TAGS_MASK) == 0 && (val & 1) == 1;  // Positive odd, no tags
}

static inline int is_heap_ref_value(int64_t val) {
    return val > 0 && (val & REF_TAGS_MASK) == 0 && (val & 1) == 0;  // Positive even (>= 2), no tags
}

static inline int32_t decode_i31_value(int64_t val) {
    int32_t raw = (int32_t)(val >> 1);
    // Sign extend from 31 bits
    if (raw & 0x40000000) {
        raw |= 0x80000000;
    }
    return raw;
}

static inline int32_t decode_heap_ref(int64_t val) {
    return (int32_t)(val >> 1);
}

static inline int32_t decode_funcref(int64_t val) {
    return (int32_t)(-val - 1);  // -(func_idx + 1) -> func_idx
}

// Check if type1 is a subtype of type2 using the type cache
static int is_subtype_cached(int type1, int type2) {
    if (type1 == type2) return 1;
    if (type1 < 0 || type1 >= g_gc_num_types) return 0;
    if (type2 < 0 || type2 >= g_gc_num_types) return 0;

    // Check canonical indices first (if available)
    if (g_gc_canonical_indices && g_gc_num_canonical > 0) {
        if (type1 < g_gc_num_canonical && type2 < g_gc_num_canonical) {
            if (g_gc_canonical_indices[type1] == g_gc_canonical_indices[type2]) {
                return 1;
            }
        }
    }

    // Walk the supertype chain
    int current = type1;
    while (current >= 0 && current < g_gc_num_types) {
        if (current == type2) return 1;
        int super_idx = g_gc_type_cache[current * 3];  // offset 0 = super_idx
        if (super_idx < 0) break;  // No more supertypes
        if (super_idx == current) break;  // Avoid infinite loop
        current = super_idx;
    }
    return 0;
}

// Abstract type indices (negative values)
#define ABSTRACT_TYPE_ANY     (-1)   // anyref
#define ABSTRACT_TYPE_EQ      (-2)   // eqref
#define ABSTRACT_TYPE_I31     (-3)   // i31ref
#define ABSTRACT_TYPE_STRUCT  (-4)   // structref (abstract)
#define ABSTRACT_TYPE_ARRAY   (-5)   // arrayref (abstract)
#define ABSTRACT_TYPE_FUNC    (-6)   // funcref
#define ABSTRACT_TYPE_EXTERN  (-7)   // externref
#define ABSTRACT_TYPE_NONE    (-8)   // nullref (bottom type for any)
#define ABSTRACT_TYPE_NOFUNC  (-9)   // nofunc (bottom type for func)
#define ABSTRACT_TYPE_NOEXTERN (-10) // noextern (bottom type for extern)

// ref.test implementation
// Returns 1 if value matches type, 0 otherwise
// value: encoded value (null=0, i31=positive odd, heap ref=positive even, funcref=negative)
// type_idx: target type index (>= 0 for concrete, < 0 for abstract)
// nullable: 1 if null is allowed, 0 otherwise
static int32_t gc_ref_test_impl(int64_t value, int32_t type_idx, int32_t nullable) {
    // Handle null
    if (is_null_value(value)) {
        return nullable ? 1 : 0;
    }

    // Handle externref values (bit 62 set) - MUST check before other types
    // Externref (host values) only match externref and anyref (via any.convert_extern)
    if (is_externref_value(value)) {
        switch (type_idx) {
            case ABSTRACT_TYPE_ANY:     // anyref - externref matches via any.convert_extern
            case ABSTRACT_TYPE_EXTERN:  // externref - direct match
                return 1;
            case ABSTRACT_TYPE_EQ:      // eqref - host externref is NOT eq
            case ABSTRACT_TYPE_I31:     // i31ref - host externref is NOT i31
            case ABSTRACT_TYPE_STRUCT:  // structref - host externref is NOT struct
            case ABSTRACT_TYPE_ARRAY:   // arrayref - host externref is NOT array
            case ABSTRACT_TYPE_FUNC:    // funcref - host externref is NOT func
            case ABSTRACT_TYPE_NONE:    // nullref - only null matches
            case ABSTRACT_TYPE_NOFUNC:  // nofunc - only null matches
            case ABSTRACT_TYPE_NOEXTERN:// noextern - only null matches
            default:
                return 0;
        }
    }

    // Handle funcref values (negative)
    if (is_funcref_value(value)) {
        // funcref matches: funcref (-6) and typed func refs (>= 0 with func kind)
        switch (type_idx) {
            case ABSTRACT_TYPE_FUNC:    // funcref - all funcs match
                return 1;
            case ABSTRACT_TYPE_NOFUNC:  // nofunc - only null matches, not funcs
            case ABSTRACT_TYPE_NONE:    // nullref - only null matches
            case ABSTRACT_TYPE_ANY:     // anyref - funcref is NOT anyref
            case ABSTRACT_TYPE_EQ:      // eqref - funcref is NOT eqref
            case ABSTRACT_TYPE_I31:     // i31ref - funcref is NOT i31
            case ABSTRACT_TYPE_STRUCT:  // structref - funcref is NOT struct
            case ABSTRACT_TYPE_ARRAY:   // arrayref - funcref is NOT array
            case ABSTRACT_TYPE_EXTERN:  // externref - funcref is NOT externref
            case ABSTRACT_TYPE_NOEXTERN: // noextern - funcref is NOT extern
                return 0;
            default:
                // For concrete type indices, check if it's a func type
                // TODO: For now, assume concrete types >= 0 with correct kind match
                // We would need type_kind info in cache to do this properly
                return 0;
        }
    }

    // Handle i31 values (positive odd)
    if (is_i31_value(value)) {
        // i31 matches: i31ref (-3), eqref (-2), anyref (-1)
        // i31 also matches externref (-7) when converted via extern.convert_any
        switch (type_idx) {
            case ABSTRACT_TYPE_ANY:     // anyref
            case ABSTRACT_TYPE_EQ:      // eqref
            case ABSTRACT_TYPE_I31:     // i31ref
            case ABSTRACT_TYPE_EXTERN:  // externref (when converted)
                return 1;
            default:
                // i31 doesn't match concrete types, structref, arrayref, funcref, nullref
                return 0;
        }
    }

    // Handle struct/array reference (positive even, heap reference)
    if (!is_heap_ref_value(value)) {
        return 0;  // Not a valid heap reference
    }

    // Value is encoded as (gc_ref << 1) where gc_ref is 1-based
    int32_t gc_ref = (int32_t)(value >> 1);
    if (gc_ref <= 0 || !g_gc_heap) {
        return 0;  // Invalid reference
    }

    // Get the object kind from heap (1=struct, 2=array)
    int32_t obj_kind = gc_heap_get_kind(g_gc_heap, gc_ref);
    int32_t obj_type_idx = gc_heap_get_type_idx(g_gc_heap, gc_ref);

    // Handle abstract types
    if (type_idx < 0) {
        switch (type_idx) {
            case ABSTRACT_TYPE_ANY:     // anyref - matches all heap objects
                return 1;
            case ABSTRACT_TYPE_EQ:      // eqref - matches struct and array
                return (obj_kind == 1 || obj_kind == 2) ? 1 : 0;
            case ABSTRACT_TYPE_STRUCT:  // structref - matches any struct
                return (obj_kind == 1) ? 1 : 0;
            case ABSTRACT_TYPE_ARRAY:   // arrayref - matches any array
                return (obj_kind == 2) ? 1 : 0;
            case ABSTRACT_TYPE_EXTERN:  // externref - struct/array match when converted
                return (obj_kind == 1 || obj_kind == 2) ? 1 : 0;
            case ABSTRACT_TYPE_I31:     // i31ref - heap objects don't match
            case ABSTRACT_TYPE_FUNC:    // funcref - heap objects don't match
            case ABSTRACT_TYPE_NONE:    // nullref - only null matches
            case ABSTRACT_TYPE_NOFUNC:  // nofunc - only null matches
            case ABSTRACT_TYPE_NOEXTERN:// noextern - only null matches
            default:
                return 0;
        }
    }

    // Handle concrete type: check if object's type is subtype of target type
    // Uses canonical indices for type equivalence checking
    if (g_gc_type_cache && obj_type_idx >= 0 && obj_type_idx < g_gc_num_types &&
        type_idx >= 0 && type_idx < g_gc_num_types) {
        // Get canonical index for target type
        int32_t target_canonical = g_gc_canonical_indices ?
            g_gc_canonical_indices[type_idx] : type_idx;

        // Walk the supertype chain to check subtyping
        int32_t current_type = obj_type_idx;
        while (current_type >= 0 && current_type < g_gc_num_types) {
            // Check canonical equivalence instead of direct index match
            int32_t current_canonical = g_gc_canonical_indices ?
                g_gc_canonical_indices[current_type] : current_type;
            if (current_canonical == target_canonical) {
                return 1;  // Found match (canonical equivalence)
            }
            // Get supertype from cache (format: [super_idx, kind, num_fields] per type)
            int32_t super_idx = g_gc_type_cache[current_type * 3];
            if (super_idx < 0 || super_idx == current_type) {
                break;  // No supertype or cycle
            }
            current_type = super_idx;
        }
    }

    return 0;  // No match found
}

// ref.cast implementation
// Returns the value if cast succeeds, traps on failure
static int64_t gc_ref_cast_impl(int64_t value, int32_t type_idx, int32_t nullable) {
    int result = gc_ref_test_impl(value, type_idx, nullable);
    if (!result) {
        // Cast failed - trigger trap
        g_trap_code = 4;  // Type mismatch
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
    }
    return value;
}

// Stub implementations for allocation and access
// These will be filled in as we implement heap access

static int64_t gc_struct_new_impl(int32_t type_idx, int64_t* fields, int32_t num_fields) {
    if (!g_gc_heap) {
        g_trap_code = 3;  // Unreachable - GC heap not set
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }

    // Handle struct.new_default: num_fields == 0 means use default values
    int64_t* actual_fields = fields;
    int32_t actual_num_fields = num_fields;
    int64_t* default_fields = NULL;

    if (num_fields == 0 && g_gc_type_cache && type_idx >= 0 && type_idx < g_gc_num_types) {
        // Get actual field count from type cache
        // Format: [super_idx, kind, num_fields] per type
        actual_num_fields = g_gc_type_cache[type_idx * 3 + 2];
        if (actual_num_fields > 0) {
            // Allocate and zero-initialize default fields
            default_fields = (int64_t*)calloc(actual_num_fields, sizeof(int64_t));
            if (!default_fields) {
                g_trap_code = 3;  // Allocation failed
                if (g_trap_active) {
                    siglongjmp(g_trap_jmp_buf, 1);
                }
                return 0;
            }
            actual_fields = default_fields;
        }
    }

    // Allocate struct and return encoded reference
    // gc_heap uses 1-based gc_ref, JIT uses (gc_ref << 1) encoding
    int32_t gc_ref = gc_heap_alloc_struct(g_gc_heap, type_idx, actual_fields, actual_num_fields);

    // Free temporary default fields buffer
    if (default_fields) {
        free(default_fields);
    }

    if (gc_ref == 0) {
        g_trap_code = 3;  // Allocation failed
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }
    // Encode for JIT: gc_ref << 1 (1-based gc_ref stays 1-based, just shifted)
    // This ensures gc_ref=1 becomes value=2, which doesn't conflict with null (0)
    int64_t encoded = ((int64_t)gc_ref) << 1;
    return encoded;
}

static int64_t gc_struct_get_impl(int64_t ref, int32_t type_idx, int32_t field_idx) {
    (void)type_idx;  // type_idx not needed for access, only for type checking
    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }
    // Decode ref: encoded as gc_ref << 1 (1-based gc_ref)
    int32_t gc_ref = (int32_t)(ref >> 1);
    return gc_heap_struct_get(g_gc_heap, gc_ref, field_idx);
}

static void gc_struct_set_impl(int64_t ref, int32_t type_idx, int32_t field_idx, int64_t value) {
    (void)type_idx;
    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }
    // Decode ref: encoded as gc_ref << 1 (1-based gc_ref)
    int32_t gc_ref = (int32_t)(ref >> 1);
    gc_heap_struct_set(g_gc_heap, gc_ref, field_idx, value);
}

static int64_t gc_array_new_impl(int32_t type_idx, int32_t len, int64_t fill) {
    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }
    int32_t gc_ref = gc_heap_alloc_array(g_gc_heap, type_idx, len, fill);
    if (gc_ref == 0) {
        g_trap_code = 3;  // Allocation failed
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }
    // Encode: gc_ref << 1 (1-based gc_ref, ensures gc_ref=1 -> value=2)
    int64_t encoded = ((int64_t)gc_ref) << 1;
    return encoded;
}

static int64_t gc_array_get_impl(int64_t ref, int32_t type_idx, int32_t idx) {
    (void)type_idx;
    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }
    // Decode: gc_ref = ref >> 1 (1-based)
    int32_t gc_ref = (int32_t)(ref >> 1);
    // Check bounds
    int32_t len = gc_heap_array_len(g_gc_heap, gc_ref);
    if (idx < 0 || idx >= len) {
        g_trap_code = 1;  // Out of bounds
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }
    return gc_heap_array_get(g_gc_heap, gc_ref, idx);
}

static void gc_array_set_impl(int64_t ref, int32_t type_idx, int32_t idx, int64_t value) {
    (void)type_idx;
    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }
    // Decode: gc_ref = ref >> 1 (1-based)
    int32_t gc_ref = (int32_t)(ref >> 1);
    // Check bounds
    int32_t len = gc_heap_array_len(g_gc_heap, gc_ref);
    if (idx < 0 || idx >= len) {
        g_trap_code = 1;  // Out of bounds
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return;
    }
    gc_heap_array_set(g_gc_heap, gc_ref, idx, value);
}

static int32_t gc_array_len_impl(int64_t ref) {
    if (!g_gc_heap) {
        g_trap_code = 3;
        if (g_trap_active) {
            siglongjmp(g_trap_jmp_buf, 1);
        }
        return 0;
    }
    // Decode: gc_ref = ref >> 1 (1-based)
    int32_t gc_ref = (int32_t)(ref >> 1);
    return gc_heap_array_len(g_gc_heap, gc_ref);
}

// FFI exports for getting function pointers

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_ref_test_ptr(void) {
    return (int64_t)gc_ref_test_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_ref_cast_ptr(void) {
    return (int64_t)gc_ref_cast_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_new_ptr(void) {
    return (int64_t)gc_struct_new_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_get_ptr(void) {
    return (int64_t)gc_struct_get_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_struct_set_ptr(void) {
    return (int64_t)gc_struct_set_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_new_ptr(void) {
    return (int64_t)gc_array_new_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_get_ptr(void) {
    return (int64_t)gc_array_get_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_set_ptr(void) {
    return (int64_t)gc_array_set_impl;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_gc_array_len_ptr(void) {
    return (int64_t)gc_array_len_impl;
}

// Type cache management

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_set_type_cache(int32_t* types_data, int num_types) {
    // Free old cache
    if (g_gc_type_cache) {
        free(g_gc_type_cache);
    }

    // Allocate and copy new cache
    // Format: [super_idx, kind, num_fields] per type (3 int32_t each)
    g_gc_num_types = num_types;
    if (num_types > 0 && types_data) {
        g_gc_type_cache = (int32_t*)malloc(num_types * 3 * sizeof(int32_t));
        if (g_gc_type_cache) {
            memcpy(g_gc_type_cache, types_data, num_types * 3 * sizeof(int32_t));
        }
    } else {
        g_gc_type_cache = NULL;
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_set_canonical_indices(int32_t* canonical, int num_types) {
    // Free old indices
    if (g_gc_canonical_indices) {
        free(g_gc_canonical_indices);
    }

    // Allocate and copy new indices
    g_gc_num_canonical = num_types;
    if (num_types > 0 && canonical) {
        g_gc_canonical_indices = (int32_t*)malloc(num_types * sizeof(int32_t));
        if (g_gc_canonical_indices) {
            memcpy(g_gc_canonical_indices, canonical, num_types * sizeof(int32_t));
        }
    } else {
        g_gc_canonical_indices = NULL;
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_clear_cache(void) {
    if (g_gc_type_cache) {
        free(g_gc_type_cache);
        g_gc_type_cache = NULL;
    }
    g_gc_num_types = 0;

    if (g_gc_canonical_indices) {
        free(g_gc_canonical_indices);
        g_gc_canonical_indices = NULL;
    }
    g_gc_num_canonical = 0;
}

// ============ GC Heap Pointer Management ============

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_set_heap(int64_t heap_ptr) {
    g_gc_heap = (GcHeap*)(uintptr_t)heap_ptr;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_gc_clear_heap(void) {
    g_gc_heap = NULL;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_gc_get_heap(void) {
    return (int64_t)(uintptr_t)g_gc_heap;
}
