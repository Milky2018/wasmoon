// Copyright 2025
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#include <time.h>
#include <signal.h>
#include <setjmp.h>

#include "moonbit.h"
#include "jit_ffi.h"

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

// ============ WASI Trampolines v2 (New ABI) ============
// These trampolines use the new JIT ABI v2:
// - X20 = context pointer (callee-saved, set before call)
// - X0-X7 = actual WASM arguments (AAPCS64 compatible)
// - No dummy func_table/mem_base parameters
// - Uses g_jit_context for memory access

// fd_write v2: (fd, iovs, iovs_len, nwritten) -> errno
static int64_t wasi_fd_write(int64_t fd, int64_t iovs, int64_t iovs_len, int64_t nwritten_ptr) {
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
            fwrite(mem + buf_ptr, 1, buf_len, (fd == 1) ? stdout : stderr);
            fflush((fd == 1) ? stdout : stderr);
            total_written += buf_len;
        }
    }

    if (nwritten_ptr > 0) {
        *(int32_t *)(mem + nwritten_ptr) = total_written;
    }

    return 0; // Success
}

// proc_exit v2: (exit_code) -> noreturn
static int64_t wasi_proc_exit(int64_t exit_code) {
    exit((int)exit_code);
    return 0; // Never reached
}

// fd_read v2: (fd, iovs, iovs_len, nread_ptr) -> errno
static int64_t wasi_fd_read(int64_t fd, int64_t iovs, int64_t iovs_len, int64_t nread_ptr) {
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

    if (nread_ptr > 0) {
        *(int32_t *)(mem + nread_ptr) = total_read;
    }

    return 0; // Success
}

// args_sizes_get v2: (argc_ptr, argv_buf_size_ptr) -> errno
static int64_t wasi_args_sizes_get(int64_t argc_ptr, int64_t argv_buf_size_ptr) {
    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;
    int argc = g_jit_context->argc;
    char **args = g_jit_context->args;

    size_t buf_size = 0;
    for (int i = 0; i < argc; i++) {
        buf_size += strlen(args[i]) + 1;
    }

    *(int32_t *)(mem + argc_ptr) = argc;
    *(int32_t *)(mem + argv_buf_size_ptr) = (int32_t)buf_size;

    return 0; // Success
}

// args_get v2: (argv_ptr, argv_buf_ptr) -> errno
static int64_t wasi_args_get(int64_t argv_ptr, int64_t argv_buf_ptr) {
    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;
    int argc = g_jit_context->argc;
    char **args = g_jit_context->args;

    int32_t buf_offset = (int32_t)argv_buf_ptr;
    for (int i = 0; i < argc; i++) {
        *(int32_t *)(mem + argv_ptr + i * 4) = buf_offset;
        size_t len = strlen(args[i]) + 1;
        memcpy(mem + buf_offset, args[i], len);
        buf_offset += (int32_t)len;
    }

    return 0; // Success
}

// environ_sizes_get v2: (environc_ptr, environ_buf_size_ptr) -> errno
static int64_t wasi_environ_sizes_get(int64_t environc_ptr, int64_t environ_buf_size_ptr) {
    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;
    int envc = g_jit_context->envc;
    char **envp = g_jit_context->envp;

    size_t buf_size = 0;
    for (int i = 0; i < envc; i++) {
        buf_size += strlen(envp[i]) + 1;
    }

    *(int32_t *)(mem + environc_ptr) = envc;
    *(int32_t *)(mem + environ_buf_size_ptr) = (int32_t)buf_size;

    return 0; // Success
}

// environ_get v2: (environ_ptr, environ_buf_ptr) -> errno
static int64_t wasi_environ_get(int64_t environ_ptr, int64_t environ_buf_ptr) {
    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;
    int envc = g_jit_context->envc;
    char **envp = g_jit_context->envp;

    int32_t buf_offset = (int32_t)environ_buf_ptr;
    for (int i = 0; i < envc; i++) {
        *(int32_t *)(mem + environ_ptr + i * 4) = buf_offset;
        size_t len = strlen(envp[i]) + 1;
        memcpy(mem + buf_offset, envp[i], len);
        buf_offset += (int32_t)len;
    }

    return 0; // Success
}

// clock_time_get v2: (clock_id, precision, time_ptr) -> errno
static int64_t wasi_clock_time_get(int64_t clock_id, int64_t precision, int64_t time_ptr) {
    (void)precision;

    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;
    int64_t time_ns = 0;

    if (clock_id == 0 || clock_id == 1) {
#ifdef _WIN32
        FILETIME ft;
        GetSystemTimeAsFileTime(&ft);
        uint64_t time_100ns = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
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

// random_get v2: (buf_ptr, buf_len) -> errno
static int64_t wasi_random_get(int64_t buf_ptr, int64_t buf_len) {
    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;

    for (int64_t i = 0; i < buf_len; i++) {
        mem[buf_ptr + i] = (uint8_t)(rand() & 0xFF);
    }

    return 0; // Success
}

// fd_close v2: (fd) -> errno
static int64_t wasi_fd_close(int64_t fd) {
    if (fd >= 0 && fd <= 2) {
        return 0; // Success
    }
    return 8; // ERRNO_BADF
}

// fd_fdstat_get v2: (fd, fdstat_ptr) -> errno
static int64_t wasi_fd_fdstat_get(int64_t fd, int64_t fdstat_ptr) {
    if (!g_jit_context || !g_jit_context->memory_base) {
        return 8; // ERRNO_BADF
    }

    uint8_t *mem = g_jit_context->memory_base;

    if (fd >= 0 && fd <= 2) {
        mem[fdstat_ptr] = 2; // FILETYPE_CHARACTER_DEVICE
        *(uint16_t *)(mem + fdstat_ptr + 2) = 0; // fs_flags
        *(uint64_t *)(mem + fdstat_ptr + 8) = 0xFFFFFFFFFFFFFFFFULL; // all rights
        *(uint64_t *)(mem + fdstat_ptr + 16) = 0xFFFFFFFFFFFFFFFFULL; // all rights
        return 0; // Success
    }
    return 8; // ERRNO_BADF
}

// fd_prestat_get v2: (fd, prestat_ptr) -> errno
static int64_t wasi_fd_prestat_get(int64_t fd, int64_t prestat_ptr) {
    (void)fd;
    (void)prestat_ptr;
    return 8; // ERRNO_BADF - no preopened directories
}

// Get v2 trampoline pointers
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_write_ptr(void) {
    return (int64_t)wasi_fd_write;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_proc_exit_ptr(void) {
    return (int64_t)wasi_proc_exit;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_read_ptr(void) {
    return (int64_t)wasi_fd_read;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_args_sizes_get_ptr(void) {
    return (int64_t)wasi_args_sizes_get;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_args_get_ptr(void) {
    return (int64_t)wasi_args_get;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_environ_sizes_get_ptr(void) {
    return (int64_t)wasi_environ_sizes_get;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_environ_get_ptr(void) {
    return (int64_t)wasi_environ_get;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_clock_time_get_ptr(void) {
    return (int64_t)wasi_clock_time_get;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_random_get_ptr(void) {
    return (int64_t)wasi_random_get;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_close_ptr(void) {
    return (int64_t)wasi_fd_close;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_fdstat_get_ptr(void) {
    return (int64_t)wasi_fd_fdstat_get;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_prestat_get_ptr(void) {
    return (int64_t)wasi_fd_prestat_get;
}
