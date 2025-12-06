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
