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

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#include <unistd.h>
#ifdef __APPLE__
#include <libkern/OSCacheControl.h>
#include <pthread.h>
#endif
#endif

#include "moonbit.h"

// ============ JIT Context for function calls ============

// JIT execution context - holds function table and memory pointer
typedef struct {
    void **func_table;      // Array of function pointers
    int func_count;         // Number of entries in func_table
    uint8_t *memory_base;   // WebAssembly linear memory base
    size_t memory_size;     // Memory size in bytes
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
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_alloc_context(int func_count) {
    jit_context_t *ctx = (jit_context_t *)malloc(sizeof(jit_context_t));
    if (!ctx) return 0;

    ctx->func_table = (void **)calloc(func_count, sizeof(void *));
    if (!ctx->func_table) {
        free(ctx);
        return 0;
    }
    ctx->func_count = func_count;
    ctx->memory_base = NULL;
    ctx->memory_size = 0;

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

// Free a JIT context
MOONBIT_FFI_EXPORT void wasmoon_jit_free_context(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (ctx) {
        if (ctx->func_table) {
            free(ctx->func_table);
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

// Get fd_write trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_write_ptr(void) {
    return (int64_t)wasi_fd_write_impl;
}

// Get proc_exit trampoline pointer
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_proc_exit_ptr(void) {
    return (int64_t)wasi_proc_exit_impl;
}

// ============ Linear Memory Allocation ============

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

// ============ Call JIT functions with context ============

// Function pointer type that receives (func_table_ptr, memory_base_ptr) as first two args
// On AArch64: X0 = func_table, X1 = memory_base
// Prologue saves them to X20 and X21 respectively
typedef int64_t (*jit_func_ctx2_i64)(int64_t func_table, int64_t mem_base);
typedef int64_t (*jit_func_ctx2_i64_i64)(int64_t func_table, int64_t mem_base, int64_t arg0);
typedef int64_t (*jit_func_ctx2_i64i64_i64)(int64_t func_table, int64_t mem_base, int64_t arg0, int64_t arg1);
typedef void (*jit_func_ctx2_void)(int64_t func_table, int64_t mem_base);
typedef void (*jit_func_ctx2_i64_void)(int64_t func_table, int64_t mem_base, int64_t arg0);
typedef void (*jit_func_ctx2_i64i64_void)(int64_t func_table, int64_t mem_base, int64_t arg0, int64_t arg1);

// Call JIT function with context: () -> i64
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_call_ctx_void_i64(int64_t func_ptr, int64_t func_table_ptr) {
    if (!func_ptr) return 0;
    int64_t mem_base = g_jit_context ? (int64_t)g_jit_context->memory_base : 0;
    jit_func_ctx2_i64 func = (jit_func_ctx2_i64)func_ptr;
    return func(func_table_ptr, mem_base);
}

// Call JIT function with context: (i64) -> i64
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_call_ctx_i64_i64(int64_t func_ptr, int64_t func_table_ptr, int64_t arg0) {
    if (!func_ptr) return 0;
    int64_t mem_base = g_jit_context ? (int64_t)g_jit_context->memory_base : 0;
    jit_func_ctx2_i64_i64 func = (jit_func_ctx2_i64_i64)func_ptr;
    return func(func_table_ptr, mem_base, arg0);
}

// Call JIT function with context: (i64, i64) -> i64
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_call_ctx_i64i64_i64(int64_t func_ptr, int64_t func_table_ptr, int64_t arg0, int64_t arg1) {
    if (!func_ptr) return 0;
    int64_t mem_base = g_jit_context ? (int64_t)g_jit_context->memory_base : 0;
    jit_func_ctx2_i64i64_i64 func = (jit_func_ctx2_i64i64_i64)func_ptr;
    return func(func_table_ptr, mem_base, arg0, arg1);
}

// Call JIT function with context: () -> void
MOONBIT_FFI_EXPORT void wasmoon_jit_call_ctx_void_void(int64_t func_ptr, int64_t func_table_ptr) {
    if (!func_ptr) return;
    int64_t mem_base = g_jit_context ? (int64_t)g_jit_context->memory_base : 0;
    jit_func_ctx2_void func = (jit_func_ctx2_void)func_ptr;
    func(func_table_ptr, mem_base);
}

// Call JIT function with context: (i64) -> void
MOONBIT_FFI_EXPORT void wasmoon_jit_call_ctx_i64_void(int64_t func_ptr, int64_t func_table_ptr, int64_t arg0) {
    if (!func_ptr) return;
    int64_t mem_base = g_jit_context ? (int64_t)g_jit_context->memory_base : 0;
    jit_func_ctx2_i64_void func = (jit_func_ctx2_i64_void)func_ptr;
    func(func_table_ptr, mem_base, arg0);
}

// Call JIT function with context: (i64, i64) -> void
MOONBIT_FFI_EXPORT void wasmoon_jit_call_ctx_i64i64_void(int64_t func_ptr, int64_t func_table_ptr, int64_t arg0, int64_t arg1) {
    if (!func_ptr) return;
    int64_t mem_base = g_jit_context ? (int64_t)g_jit_context->memory_base : 0;
    jit_func_ctx2_i64i64_void func = (jit_func_ctx2_i64i64_void)func_ptr;
    func(func_table_ptr, mem_base, arg0, arg1);
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

// Function pointer types for different signatures
typedef int64_t (*jit_func_void_i64)(void);
typedef int64_t (*jit_func_i64_i64)(int64_t);
typedef int64_t (*jit_func_i64i64_i64)(int64_t, int64_t);
typedef int64_t (*jit_func_i64i64i64_i64)(int64_t, int64_t, int64_t);
typedef int64_t (*jit_func_i64i64i64i64_i64)(int64_t, int64_t, int64_t, int64_t);
typedef void (*jit_func_void_void)(void);
typedef void (*jit_func_i64_void)(int64_t);
typedef void (*jit_func_i64i64_void)(int64_t, int64_t);
typedef void (*jit_func_i64i64i64_void)(int64_t, int64_t, int64_t);
typedef void (*jit_func_i64i64i64i64_void)(int64_t, int64_t, int64_t, int64_t);

// Call a JIT-compiled function with no arguments, returning i64
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_call_void_i64(int64_t func_ptr) {
    if (!func_ptr) return 0;
    jit_func_void_i64 func = (jit_func_void_i64)func_ptr;
    return func();
}

// Call a JIT-compiled function with 1 i64 argument, returning i64
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_call_i64_i64(int64_t func_ptr, int64_t arg0) {
    if (!func_ptr) return 0;
    jit_func_i64_i64 func = (jit_func_i64_i64)func_ptr;
    return func(arg0);
}

// Call a JIT-compiled function with 2 i64 arguments, returning i64
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_call_i64i64_i64(int64_t func_ptr, int64_t arg0, int64_t arg1) {
    if (!func_ptr) return 0;
    jit_func_i64i64_i64 func = (jit_func_i64i64_i64)func_ptr;
    return func(arg0, arg1);
}

// Call a JIT-compiled function with 3 i64 arguments, returning i64
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_call_i64i64i64_i64(int64_t func_ptr, int64_t arg0, int64_t arg1, int64_t arg2) {
    if (!func_ptr) return 0;
    jit_func_i64i64i64_i64 func = (jit_func_i64i64i64_i64)func_ptr;
    return func(arg0, arg1, arg2);
}

// Call a JIT-compiled function with 4 i64 arguments, returning i64
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_call_i64i64i64i64_i64(int64_t func_ptr, int64_t arg0, int64_t arg1, int64_t arg2, int64_t arg3) {
    if (!func_ptr) return 0;
    jit_func_i64i64i64i64_i64 func = (jit_func_i64i64i64i64_i64)func_ptr;
    return func(arg0, arg1, arg2, arg3);
}

// Call a JIT-compiled function with no arguments, no return
MOONBIT_FFI_EXPORT void wasmoon_jit_call_void_void(int64_t func_ptr) {
    if (!func_ptr) return;
    jit_func_void_void func = (jit_func_void_void)func_ptr;
    func();
}

// Call a JIT-compiled function with 1 i64 argument, no return
MOONBIT_FFI_EXPORT void wasmoon_jit_call_i64_void(int64_t func_ptr, int64_t arg0) {
    if (!func_ptr) return;
    jit_func_i64_void func = (jit_func_i64_void)func_ptr;
    func(arg0);
}

// Call a JIT-compiled function with 2 i64 arguments, no return
MOONBIT_FFI_EXPORT void wasmoon_jit_call_i64i64_void(int64_t func_ptr, int64_t arg0, int64_t arg1) {
    if (!func_ptr) return;
    jit_func_i64i64_void func = (jit_func_i64i64_void)func_ptr;
    func(arg0, arg1);
}

// Call a JIT-compiled function with 3 i64 arguments, no return
MOONBIT_FFI_EXPORT void wasmoon_jit_call_i64i64i64_void(int64_t func_ptr, int64_t arg0, int64_t arg1, int64_t arg2) {
    if (!func_ptr) return;
    jit_func_i64i64i64_void func = (jit_func_i64i64i64_void)func_ptr;
    func(arg0, arg1, arg2);
}

// Call a JIT-compiled function with 4 i64 arguments, no return
MOONBIT_FFI_EXPORT void wasmoon_jit_call_i64i64i64i64_void(int64_t func_ptr, int64_t arg0, int64_t arg1, int64_t arg2, int64_t arg3) {
    if (!func_ptr) return;
    jit_func_i64i64i64i64_void func = (jit_func_i64i64i64i64_void)func_ptr;
    func(arg0, arg1, arg2, arg3);
}

// Generic call with array of arguments (up to 8 args)
// Returns result in out_result (if not NULL)
// sig: bit 0 = has_result, bits 1-4 = num_args
MOONBIT_FFI_EXPORT int wasmoon_jit_call_generic(void *func_ptr, int sig,
                                                  int64_t *args, int64_t *out_result) {
    if (!func_ptr) return -1;

    int has_result = sig & 1;
    int num_args = (sig >> 1) & 0xF;

    int64_t result = 0;

    // Use the appropriate call based on num_args
    switch (num_args) {
        case 0:
            if (has_result) {
                result = ((jit_func_void_i64)func_ptr)();
            } else {
                ((jit_func_void_void)func_ptr)();
            }
            break;
        case 1:
            if (has_result) {
                result = ((jit_func_i64_i64)func_ptr)(args[0]);
            } else {
                ((jit_func_i64_void)func_ptr)(args[0]);
            }
            break;
        case 2:
            if (has_result) {
                result = ((jit_func_i64i64_i64)func_ptr)(args[0], args[1]);
            } else {
                ((jit_func_i64i64_void)func_ptr)(args[0], args[1]);
            }
            break;
        case 3:
            if (has_result) {
                result = ((jit_func_i64i64i64_i64)func_ptr)(args[0], args[1], args[2]);
            } else {
                ((jit_func_i64i64i64_void)func_ptr)(args[0], args[1], args[2]);
            }
            break;
        case 4:
            if (has_result) {
                result = ((jit_func_i64i64i64i64_i64)func_ptr)(args[0], args[1], args[2], args[3]);
            } else {
                ((jit_func_i64i64i64i64_void)func_ptr)(args[0], args[1], args[2], args[3]);
            }
            break;
        default:
            return -2;  // Too many arguments
    }

    if (out_result && has_result) {
        *out_result = result;
    }

    return 0;
}

// Debug: print machine code bytes
MOONBIT_FFI_EXPORT void wasmoon_jit_debug_print_code(int64_t ptr_i64, int size) {
    void *ptr = (void *)ptr_i64;
    if (!ptr || size <= 0) return;
    unsigned char *bytes = (unsigned char *)ptr;
    printf("JIT code at %p (%d bytes):\n", ptr, size);
    for (int i = 0; i < size; i++) {
        printf("%02x ", bytes[i]);
        if ((i + 1) % 16 == 0) printf("\n");
    }
    if (size % 16 != 0) printf("\n");
}

#ifdef __cplusplus
}
#endif
