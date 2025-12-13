// Copyright 2025
// JIT runtime FFI implementation
// Provides executable memory allocation and function invocation

#ifdef __cplusplus
extern "C" {
#endif

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

// ============ Trap Handling ============
// Jump buffer for catching JIT traps (BRK instructions and stack overflow)
// Using sigjmp_buf/sigsetjmp/siglongjmp for proper signal handler support
static sigjmp_buf g_trap_jmp_buf;
static volatile sig_atomic_t g_trap_code = 0;
static volatile sig_atomic_t g_trap_active = 0;

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
static void install_trap_handler(void) {
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

// ============ JIT Context for function calls ============

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

// Global JIT context (set before calling JIT functions)
static jit_context_t *g_jit_context = NULL;

// Set the global JIT context
MOONBIT_FFI_EXPORT void wasmoon_jit_set_context(int64_t ctx_ptr) {
    g_jit_context = (jit_context_t *)ctx_ptr;
}

// Get the global JIT context
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_context(void) {
    return (int64_t)g_jit_context;
}

// Allocate a JIT context
// Memory layout for func_table:
//   [indirect_table_ptr | func_ptr_0 | func_ptr_1 | ...]
//   ^                    ^
//   raw_alloc            func_table (returned pointer, offset +8)
// This allows LDR X24, [X20, #-8] to load indirect_table_ptr in prologue
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_alloc_context(int func_count) {
    jit_context_t *ctx = (jit_context_t *)malloc(sizeof(jit_context_t));
    if (!ctx) return 0;

    // Allocate func_count + 1 entries: first slot for indirect_table_ptr
    void **raw_alloc = (void **)calloc(func_count + 1, sizeof(void *));
    if (!raw_alloc) {
        free(ctx);
        return 0;
    }
    // func_table points to second element, so func_table[-1] = indirect_table_ptr
    ctx->func_table = raw_alloc + 1;
    // Initialize indirect_table_ptr slot to NULL (will be set when indirect table is allocated)
    raw_alloc[0] = NULL;
    ctx->func_count = func_count;
    ctx->indirect_table = NULL;
    ctx->indirect_count = 0;
    ctx->memory_base = NULL;
    ctx->memory_size = 0;
    ctx->args = NULL;
    ctx->argc = 0;
    ctx->envp = NULL;
    ctx->envc = 0;

    return (int64_t)ctx;
}

// Set a function pointer in the context
MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_func(int64_t ctx_ptr, int idx, int64_t func_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx && idx >= 0 && idx < ctx->func_count) {
        ctx->func_table[idx] = (void *)func_ptr;
    }
}

// Set memory in the context
MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_memory(int64_t ctx_ptr, int64_t mem_ptr, int64_t mem_size) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx) {
        ctx->memory_base = (uint8_t *)mem_ptr;
        ctx->memory_size = (size_t)mem_size;
    }
}

// Get function table base address
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_get_func_table(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx) {
        return (int64_t)ctx->func_table;
    }
    return 0;
}

// Allocate indirect table for call_indirect
// This table is separate from func_table and used only for call_indirect
MOONBIT_FFI_EXPORT int wasmoon_jit_ctx_alloc_indirect_table(int64_t ctx_ptr, int count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || count <= 0) return 0;

    // Free existing indirect table if any
    if (ctx->indirect_table) {
        free(ctx->indirect_table);
    }

    // Allocate exactly 'count' entries for the WASM table
    ctx->indirect_table = (void **)calloc(count, sizeof(void *));
    if (!ctx->indirect_table) {
        ctx->indirect_count = 0;
        return 0;
    }
    ctx->indirect_count = count;

    // Store indirect_table pointer in func_table[-1] for prologue to load
    // This is accessed via LDR X24, [X20, #-8]
    ctx->func_table[-1] = ctx->indirect_table;

    return 1;
}

// Set an entry in indirect table
// table_idx: the WASM table index (0, 1, 2, ...)
// func_idx: the function index to look up in func_table
MOONBIT_FFI_EXPORT void wasmoon_jit_ctx_set_indirect(int64_t ctx_ptr, int table_idx, int func_idx) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx && ctx->indirect_table &&
        table_idx >= 0 && table_idx < ctx->indirect_count &&
        func_idx >= 0 && func_idx < ctx->func_count) {
        ctx->indirect_table[table_idx] = ctx->func_table[func_idx];
    }
}

// Get indirect table base address (this is what X20 should point to for call_indirect)
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_ctx_get_indirect_table(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx && ctx->indirect_table) {
        return (int64_t)ctx->indirect_table;
    }
    // Fall back to func_table if no indirect table (backward compatibility)
    if (ctx) {
        return (int64_t)ctx->func_table;
    }
    return 0;
}

// Free a JIT context
MOONBIT_FFI_EXPORT void wasmoon_jit_free_context(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx) {
        if (ctx->func_table) {
            // func_table points to raw_alloc + 1, so subtract 1 to get original allocation
            free(ctx->func_table - 1);
        }
        if (ctx->indirect_table) {
            free(ctx->indirect_table);
        }
        free(ctx);
    }
}

// ============ WASI Trampolines ============
// These trampolines use the JIT ABI:
// X0 = func_table_ptr (ignored), X1 = memory_base (ignored since we use global context)
// X2, X3, ... = actual WASM arguments

// fd_write trampoline: (func_table, mem_base, fd, iovs, iovs_len, nwritten) -> errno
// Note: The first two args (func_table, mem_base) are passed by JIT calling convention
// but we use the global context for memory access
static int64_t wasi_fd_write_impl(int64_t func_table, int64_t mem_base, int64_t fd, int64_t iovs, int64_t iovs_len, int64_t nwritten_ptr) {
    (void)func_table;  // unused
    (void)mem_base;    // we use global context instead

    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;
    int32_t total_written = 0;

    // Only handle stdout (1) and stderr (2)
    if (fd != 1 && fd != 2) {
        return 8; // ERRNO_BADF
    }

    for (int64_t i = 0; i < iovs_len; i++) {
        int32_t iov_offset = (int32_t)(iovs + i * 8);
        int32_t buf_ptr = *(int32_t *)(mem + iov_offset);
        int32_t buf_len = *(int32_t *)(mem + iov_offset + 4);

        if (buf_len > 0) {
            // Write to stdout/stderr
            fwrite(mem + buf_ptr, 1, buf_len, (fd == 1) ? stdout : stderr);
            fflush((fd == 1) ? stdout : stderr);
            total_written += buf_len;
        }
    }

    // Write the number of bytes written
    if (nwritten_ptr > 0) {
        *(int32_t *)(mem + nwritten_ptr) = total_written;
    }

    return 0; // Success
}

// proc_exit trampoline: (func_table, mem_base, exit_code) -> noreturn
// Note: The first two args are JIT calling convention overhead
static int64_t wasi_proc_exit_impl(int64_t func_table, int64_t mem_base, int64_t exit_code) {
    (void)func_table;
    (void)mem_base;
    exit((int)exit_code);
    return 0; // Never reached
}

// fd_read trampoline: (func_table, mem_base, fd, iovs, iovs_len, nread_ptr) -> errno
// Only supports stdin (fd=0)
static int64_t wasi_fd_read_impl(int64_t func_table, int64_t mem_base, int64_t fd, int64_t iovs, int64_t iovs_len, int64_t nread_ptr) {
    (void)func_table;
    (void)mem_base;

    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;
    int32_t total_read = 0;

    // Only handle stdin (0)
    if (fd != 0) {
        return 8; // ERRNO_BADF
    }

    for (int64_t i = 0; i < iovs_len; i++) {
        int32_t iov_offset = (int32_t)(iovs + i * 8);
        int32_t buf_ptr = *(int32_t *)(mem + iov_offset);
        int32_t buf_len = *(int32_t *)(mem + iov_offset + 4);

        if (buf_len > 0) {
            size_t bytes_read = fread(mem + buf_ptr, 1, buf_len, stdin);
            total_read += (int32_t)bytes_read;
            if (bytes_read < (size_t)buf_len) {
                break; // EOF or error
            }
        }
    }

    // Write the number of bytes read
    if (nread_ptr > 0) {
        *(int32_t *)(mem + nread_ptr) = total_read;
    }

    return 0; // Success
}

// args_sizes_get trampoline: (func_table, mem_base, argc_ptr, argv_buf_size_ptr) -> errno
static int64_t wasi_args_sizes_get_impl(int64_t func_table, int64_t mem_base, int64_t argc_ptr, int64_t argv_buf_size_ptr) {
    (void)func_table;
    (void)mem_base;

    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;
    int argc = g_jit_context->argc;
    char **args = g_jit_context->args;

    // Calculate total buffer size
    size_t buf_size = 0;
    for (int i = 0; i < argc; i++) {
        buf_size += strlen(args[i]) + 1; // +1 for null terminator
    }

    *(int32_t *)(mem + argc_ptr) = argc;
    *(int32_t *)(mem + argv_buf_size_ptr) = (int32_t)buf_size;

    return 0; // Success
}

// args_get trampoline: (func_table, mem_base, argv_ptr, argv_buf_ptr) -> errno
static int64_t wasi_args_get_impl(int64_t func_table, int64_t mem_base, int64_t argv_ptr, int64_t argv_buf_ptr) {
    (void)func_table;
    (void)mem_base;

    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;
    int argc = g_jit_context->argc;
    char **args = g_jit_context->args;

    int32_t buf_offset = (int32_t)argv_buf_ptr;
    for (int i = 0; i < argc; i++) {
        // Store pointer to string in argv array
        *(int32_t *)(mem + argv_ptr + i * 4) = buf_offset;
        // Copy string to buffer
        size_t len = strlen(args[i]) + 1;
        memcpy(mem + buf_offset, args[i], len);
        buf_offset += (int32_t)len;
    }

    return 0; // Success
}

// environ_sizes_get trampoline: (func_table, mem_base, environc_ptr, environ_buf_size_ptr) -> errno
static int64_t wasi_environ_sizes_get_impl(int64_t func_table, int64_t mem_base, int64_t environc_ptr, int64_t environ_buf_size_ptr) {
    (void)func_table;
    (void)mem_base;

    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;
    int envc = g_jit_context->envc;
    char **envp = g_jit_context->envp;

    // Calculate total buffer size
    size_t buf_size = 0;
    for (int i = 0; i < envc; i++) {
        buf_size += strlen(envp[i]) + 1; // +1 for null terminator
    }

    *(int32_t *)(mem + environc_ptr) = envc;
    *(int32_t *)(mem + environ_buf_size_ptr) = (int32_t)buf_size;

    return 0; // Success
}

// environ_get trampoline: (func_table, mem_base, environ_ptr, environ_buf_ptr) -> errno
static int64_t wasi_environ_get_impl(int64_t func_table, int64_t mem_base, int64_t environ_ptr, int64_t environ_buf_ptr) {
    (void)func_table;
    (void)mem_base;

    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;
    int envc = g_jit_context->envc;
    char **envp = g_jit_context->envp;

    int32_t buf_offset = (int32_t)environ_buf_ptr;
    for (int i = 0; i < envc; i++) {
        // Store pointer to string in environ array
        *(int32_t *)(mem + environ_ptr + i * 4) = buf_offset;
        // Copy string to buffer
        size_t len = strlen(envp[i]) + 1;
        memcpy(mem + buf_offset, envp[i], len);
        buf_offset += (int32_t)len;
    }

    return 0; // Success
}

// clock_time_get trampoline: (func_table, mem_base, clock_id, precision, time_ptr) -> errno
static int64_t wasi_clock_time_get_impl(int64_t func_table, int64_t mem_base, int64_t clock_id, int64_t precision, int64_t time_ptr) {
    (void)func_table;
    (void)mem_base;
    (void)precision;

    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;
    int64_t time_ns = 0;

    // clock_id: 0 = realtime, 1 = monotonic
    if (clock_id == 0 || clock_id == 1) {
#ifdef _WIN32
        FILETIME ft;
        GetSystemTimeAsFileTime(&ft);
        uint64_t time_100ns = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
        // Convert from 100ns intervals since 1601 to ns since 1970
        time_ns = (int64_t)((time_100ns - 116444736000000000ULL) * 100);
#else
        struct timespec ts;
        clock_gettime(clock_id == 0 ? CLOCK_REALTIME : CLOCK_MONOTONIC, &ts);
        time_ns = (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
    } else {
        return 28; // ERRNO_INVAL
    }

    *(int64_t *)(mem + time_ptr) = time_ns;
    return 0; // Success
}

// random_get trampoline: (func_table, mem_base, buf_ptr, buf_len) -> errno
static int64_t wasi_random_get_impl(int64_t func_table, int64_t mem_base, int64_t buf_ptr, int64_t buf_len) {
    (void)func_table;
    (void)mem_base;

    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;

    // Simple PRNG - not cryptographically secure
    for (int64_t i = 0; i < buf_len; i++) {
        mem[buf_ptr + i] = (uint8_t)(rand() & 0xFF);
    }

    return 0; // Success
}

// fd_close trampoline: (func_table, mem_base, fd) -> errno
// Stub - just returns success for stdio fds
static int64_t wasi_fd_close_impl(int64_t func_table, int64_t mem_base, int64_t fd) {
    (void)func_table;
    (void)mem_base;

    // For stdio fds (0, 1, 2), just return success
    if (fd >= 0 && fd <= 2) {
        return 0; // Success
    }
    return 8; // ERRNO_BADF
}

// fd_fdstat_get trampoline: (func_table, mem_base, fd, fdstat_ptr) -> errno
static int64_t wasi_fd_fdstat_get_impl(int64_t func_table, int64_t mem_base, int64_t fd, int64_t fdstat_ptr) {
    (void)func_table;
    (void)mem_base;

    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;

    // For stdio fds (0, 1, 2), return basic fdstat
    if (fd >= 0 && fd <= 2) {
        // fdstat structure:
        // u8 fs_filetype
        // u16 fs_flags
        // u64 fs_rights_base
        // u64 fs_rights_inheriting
        mem[fdstat_ptr] = 2; // FILETYPE_CHARACTER_DEVICE
        *(uint16_t *)(mem + fdstat_ptr + 2) = 0; // fs_flags
        *(uint64_t *)(mem + fdstat_ptr + 8) = 0xFFFFFFFFFFFFFFFFULL; // all rights
        *(uint64_t *)(mem + fdstat_ptr + 16) = 0xFFFFFFFFFFFFFFFFULL; // all rights
        return 0; // Success
    }
    return 8; // ERRNO_BADF
}

// fd_prestat_get trampoline: (func_table, mem_base, fd, prestat_ptr) -> errno
// Returns BADF for now (no preopened directories in JIT mode)
static int64_t wasi_fd_prestat_get_impl(int64_t func_table, int64_t mem_base, int64_t fd, int64_t prestat_ptr) {
    (void)func_table;
    (void)mem_base;
    (void)fd;
    (void)prestat_ptr;
    return 8; // ERRNO_BADF - no preopened directories
}

// Get fd_write trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_write_ptr(void) {
    return (int64_t)wasi_fd_write_impl;
}

// Get proc_exit trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_proc_exit_ptr(void) {
    return (int64_t)wasi_proc_exit_impl;
}

// Get fd_read trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_read_ptr(void) {
    return (int64_t)wasi_fd_read_impl;
}

// Get args_sizes_get trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_args_sizes_get_ptr(void) {
    return (int64_t)wasi_args_sizes_get_impl;
}

// Get args_get trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_args_get_ptr(void) {
    return (int64_t)wasi_args_get_impl;
}

// Get environ_sizes_get trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_environ_sizes_get_ptr(void) {
    return (int64_t)wasi_environ_sizes_get_impl;
}

// Get environ_get trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_environ_get_ptr(void) {
    return (int64_t)wasi_environ_get_impl;
}

// Get clock_time_get trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_clock_time_get_ptr(void) {
    return (int64_t)wasi_clock_time_get_impl;
}

// Get random_get trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_random_get_ptr(void) {
    return (int64_t)wasi_random_get_impl;
}

// Get fd_close trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_close_ptr(void) {
    return (int64_t)wasi_fd_close_impl;
}

// Get fd_fdstat_get trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_fdstat_get_ptr(void) {
    return (int64_t)wasi_fd_fdstat_get_impl;
}

// Get fd_prestat_get trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_prestat_get_ptr(void) {
    return (int64_t)wasi_fd_prestat_get_impl;
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

// Grow linear memory by delta pages
// Returns the previous size in pages, or -1 on failure
// max_pages: maximum allowed pages (0 means no limit, use 65536 as default max)
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

// Get current memory size in pages
MOONBIT_FFI_EXPORT int32_t wasmoon_jit_memory_size(void) {
    if (!g_jit_context) return 0;
    return (int32_t)(g_jit_context->memory_size / WASM_PAGE_SIZE);
}

// Get current memory base (for reloading after memory.grow)
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_base(void) {
    if (!g_jit_context) return 0;
    return (int64_t)g_jit_context->memory_base;
}

// Get current memory size in bytes (for reloading after memory.grow)
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_size_bytes(void) {
    if (!g_jit_context) return 0;
    return (int64_t)g_jit_context->memory_size;
}

// Get function pointer for memory_grow (for JIT to call directly)
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_grow_ptr(void) {
    return (int64_t)wasmoon_jit_memory_grow;
}

// Get function pointer for get_memory_base (for JIT to call directly)
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_base_ptr(void) {
    return (int64_t)wasmoon_jit_get_memory_base;
}

// Get function pointer for get_memory_size_bytes (for JIT to call directly)
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_memory_size_bytes_ptr(void) {
    return (int64_t)wasmoon_jit_get_memory_size_bytes;
}

// Get function pointer for memory_size (for JIT to call directly)
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
// All JIT calls go through wasmoon_jit_call_multi_return
// - JIT ABI: X0 = func_table, X1 = mem_base, X2 = mem_size, X3 = indirect_table, X4-X10 = args
// - When >2 int or >2 float returns: X7 = extra_results_buffer pointer
// - Returns: X0/X1 for first 2 ints, D0/D1 for first 2 floats
// - Extra returns: callee writes to buffer pointed by X7 (saved to X23)

// Call a JIT function that returns multiple values
// result_types: array of type codes (0=I32, 1=I64, 2=F32, 3=F64)
// num_results: number of return values
// Returns: 0 on success, trap code on error
// Note: indirect_table_ptr is stored at func_table[-1] and loaded by prologue into X24
MOONBIT_FFI_EXPORT int wasmoon_jit_call_multi_return(
    int64_t func_ptr,
    int64_t func_table_ptr,
    int64_t* args,
    int num_args,
    int64_t* results,
    int* result_types,
    int num_results
) {
    if (!func_ptr) return -1;

    // CRITICAL: Save the parameters that are used AFTER the BLR call.
    // The compiler may allocate these in registers that get clobbered by our
    // register setup for the JIT call. By saving them to volatile locals
    // RIGHT AWAY (before any other code), we force them onto the stack
    // where they won't be corrupted by our inline asm.
    volatile int saved_num_results = num_results;
    volatile int64_t *saved_results = results;
    volatile int *saved_result_types = result_types;

    install_trap_handler();
    g_trap_code = 0;
    g_trap_active = 1;

    if (sigsetjmp(g_trap_jmp_buf, 1) != 0) {
        g_trap_active = 0;
        return (int)g_trap_code;
    }

    int64_t mem_base = g_jit_context ? (int64_t)g_jit_context->memory_base : 0;
    int64_t mem_size = g_jit_context ? (int64_t)g_jit_context->memory_size : 0;

    // Count how many extra results need buffer
    int int_count = 0, float_count = 0;
    for (int i = 0; i < num_results; i++) {
        if (result_types[i] == 2 || result_types[i] == 3) { // F32 or F64
            float_count++;
        } else { // I32, I64
            int_count++;
        }
    }
    int needs_extra_buffer = (int_count > 2 || float_count > 2);

    // Buffer for extra results
    int64_t extra_buffer[16];
    memset(extra_buffer, 0, sizeof(extra_buffer));

    // Call the JIT function
    int64_t x0_result = 0, x1_result = 0;
    uint64_t d0_bits = 0, d1_bits = 0;

#if defined(__aarch64__) || defined(_M_ARM64)
    // JIT ABI: X0=func_table, X1=mem_base, X2=mem_size, X3-X10=args (up to 8 register args)
    // Args 8+ go on the stack at [SP + (i-8)*8]
    // indirect_table_ptr is stored at func_table[-1] and loaded into X24 by prologue
    // When needs_extra_buffer: X7=extra_results_buffer (conflicts with arg 4)

    // Calculate stack args (args beyond the first 8 register args)
    int max_reg_args = 8;
    int stack_args = (num_args > max_reg_args) ? (num_args - max_reg_args) : 0;
    // Stack must be 16-byte aligned
    int stack_space = ((stack_args * 8) + 15) & ~15;

    // For stack args, allocate space and store them BEFORE setting up register args
    // (C code in the loop may clobber register variables)
    if (stack_space > 0) {
        // Allocate stack space and get pointer to it
        int64_t *stack_args_ptr;
        __asm__ volatile(
            "sub sp, sp, %[size]\n\t"
            "mov %[ptr], sp"
            : [ptr] "=r"(stack_args_ptr)
            : [size] "r"((int64_t)stack_space)
        );

        // Store all stack args directly from args array
        for (int i = 0; i < stack_args; i++) {
            stack_args_ptr[i] = args[8 + i];
        }
    }

    // Set up register arguments AFTER the C loop to avoid clobbering
    register int64_t r0 __asm__("x0") = func_table_ptr;
    register int64_t r1 __asm__("x1") = mem_base;
    register int64_t r2 __asm__("x2") = mem_size;
    register int64_t r3 __asm__("x3") = num_args > 0 ? args[0] : 0;
    register int64_t r4 __asm__("x4") = num_args > 1 ? args[1] : 0;
    register int64_t r5 __asm__("x5") = num_args > 2 ? args[2] : 0;
    register int64_t r6 __asm__("x6") = num_args > 3 ? args[3] : 0;
    // X7 is used for extra_results_buffer OR arg 4
    register int64_t r7 __asm__("x7") = needs_extra_buffer ? (int64_t)extra_buffer : (num_args > 4 ? args[4] : 0);
    // X8-X10 for args 5-7 (only used when needs_extra_buffer is false)
    register int64_t r8 __asm__("x8") = num_args > 5 ? args[5] : 0;
    register int64_t r9 __asm__("x9") = num_args > 6 ? args[6] : 0;
    register int64_t r10 __asm__("x10") = num_args > 7 ? args[7] : 0;
    register uint64_t d0 __asm__("d0");
    register uint64_t d1 __asm__("d1");

    if (stack_space > 0) {
        __asm__ volatile(
            "blr %[func]\n\t"
            "add sp, sp, %[size]"
            : "+r"(r0), "+r"(r1), "=w"(d0), "=w"(d1)
            : [func] "r"(func_ptr), "r"(r2), "r"(r3), "r"(r4), "r"(r5), "r"(r6), "r"(r7), "r"(r8), "r"(r9), "r"(r10),
              [size] "r"((int64_t)stack_space)
            : "x11", "x12", "x13", "x14", "x15", "x16", "x17", "x30",
              "d2", "d3", "d4", "d5", "d6", "d7",
              "d16", "d17", "d18", "d19", "d20", "d21", "d22", "d23",
              "d24", "d25", "d26", "d27", "d28", "d29", "d30", "d31",
              "memory", "cc"
        );
    } else {
        __asm__ volatile(
            "blr %[func]"
            : "+r"(r0), "+r"(r1), "=w"(d0), "=w"(d1)
            : [func] "r"(func_ptr), "r"(r2), "r"(r3), "r"(r4), "r"(r5), "r"(r6), "r"(r7), "r"(r8), "r"(r9), "r"(r10)
            : "x11", "x12", "x13", "x14", "x15",
              "x16", "x17", "x30",
              "d2", "d3", "d4", "d5", "d6", "d7",
              "d16", "d17", "d18", "d19", "d20", "d21", "d22", "d23",
              "d24", "d25", "d26", "d27", "d28", "d29", "d30", "d31",
              "memory", "cc"
        );
    }

    x0_result = r0;
    x1_result = r1;
    d0_bits = d0;
    d1_bits = d1;
#else
    // Fallback for non-ARM64 platforms
    typedef int64_t (*jit_func_t)(int64_t, int64_t, int64_t);
    x0_result = ((jit_func_t)func_ptr)(func_table_ptr, mem_base, mem_size);
#endif

    g_trap_active = 0;

    // Distribute results from registers and extra_buffer to the output array
    int int_idx = 0, float_idx = 0, extra_idx = 0;
    for (int i = 0; i < saved_num_results; i++) {
        int ty = saved_result_types[i];
        if (ty == 2) { // F32 - stored as raw 32-bit in S register (lower 32 bits of D)
            if (float_idx < 2) {
                // From S0 or S1 (lower 32 bits of D0 or D1)
                // d0_bits/d1_bits contain the raw 64-bit value from D register
                // For f32, the value is in the lower 32 bits (S register is low half of D)
                uint64_t bits = (float_idx == 0) ? d0_bits : d1_bits;
                uint32_t float_bits = (uint32_t)(bits & 0xFFFFFFFF);
                // Store as int64 with float bits in lower 32 bits
                saved_results[i] = (int64_t)float_bits;
                float_idx++;
            } else {
                // From extra buffer
                saved_results[i] = extra_buffer[extra_idx++];
            }
        } else if (ty == 3) { // F64
            if (float_idx < 2) {
                // From D0 or D1 - raw 64-bit value is the f64 bit pattern
                uint64_t bits = (float_idx == 0) ? d0_bits : d1_bits;
                saved_results[i] = (int64_t)bits;
                float_idx++;
            } else {
                // From extra buffer
                saved_results[i] = extra_buffer[extra_idx++];
            }
        } else { // I32, I64
            if (int_idx < 2) {
                // From X0 or X1
                saved_results[i] = (int_idx == 0) ? x0_result : x1_result;
                int_idx++;
            } else {
                // From extra buffer
                saved_results[i] = extra_buffer[extra_idx++];
            }
        }
    }

    return 0; // Success
}

// ============ Executable memory management ============

// Executable memory block
typedef struct {
    void *code;
    size_t size;
} jit_code_block_t;

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

// Free executable memory
MOONBIT_FFI_EXPORT int wasmoon_jit_free_exec(int64_t ptr_i64) {
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

#ifdef __cplusplus
}
#endif
