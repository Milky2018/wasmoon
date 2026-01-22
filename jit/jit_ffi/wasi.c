// Copyright 2025
// Full WASI Preview1 implementation for JIT mode
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>
#include <time.h>
#include <signal.h>
#include <setjmp.h>

#ifndef _WIN32
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <dirent.h>
#include <poll.h>
#include <sys/socket.h>
#include <sched.h>
#ifdef __linux__
#include <sys/random.h>
#endif
#else
#include <windows.h>
#include <bcrypt.h>
#endif

#include "moonbit.h"
#include "jit_internal.h"

// ============ WASI Error Codes ============
#define WASI_ESUCCESS     0
#define WASI_E2BIG        1
#define WASI_EACCES       2
#define WASI_EBADF        8
#define WASI_EEXIST       20
#define WASI_EINVAL       28
#define WASI_EIO          29
#define WASI_EISDIR       31
#define WASI_ENOENT       44
#define WASI_ENOMEM       48
#define WASI_ENOSYS       52
#define WASI_ENOTDIR      54
#define WASI_ENOTEMPTY    55
#define WASI_ESPIPE       70
#define WASI_ENAMETOOLONG 37
#define WASI_EFAULT       21
#define WASI_TRAP_EXIT    100

// ============ WASI File Types ============
#define WASI_FILETYPE_UNKNOWN          0
#define WASI_FILETYPE_BLOCK_DEVICE     1
#define WASI_FILETYPE_CHARACTER_DEVICE 2
#define WASI_FILETYPE_DIRECTORY        3
#define WASI_FILETYPE_REGULAR_FILE     4
#define WASI_FILETYPE_SOCKET_DGRAM     5
#define WASI_FILETYPE_SOCKET_STREAM    6
#define WASI_FILETYPE_SYMBOLIC_LINK    7

// WASI rights: valid bits are 0-28
#define WASI_RIGHTS_ALL_VALID ((uint64_t)((1ULL << 29) - 1))

// ============ Helper Functions ============

// Get native fd from WASI fd
static int get_native_fd(jit_context_t *ctx, int wasi_fd) {
    if (wasi_fd < 0) return -1;
    // Check fd table for all fds (including stdio for quiet mode support)
    if (!ctx->fd_table || wasi_fd >= ctx->fd_table_size) {
        // Fallback: stdio fds map directly if no fd_table
        if (wasi_fd < 3) return wasi_fd;
        return -1;
    }
    return ctx->fd_table[wasi_fd];
}

// Check if fd is a preopen directory
static int is_preopen_fd(jit_context_t *ctx, int wasi_fd) {
    if (!ctx->preopen_paths) return 0;
    int idx = wasi_fd - ctx->preopen_base_fd;
    return idx >= 0 && idx < ctx->preopen_count;
}

// Get preopen host path
static const char* get_preopen_path(jit_context_t *ctx, int wasi_fd) {
    if (!is_preopen_fd(ctx, wasi_fd)) return NULL;
    int idx = wasi_fd - ctx->preopen_base_fd;
    return ctx->preopen_paths[idx];
}

static const char* get_open_dir_path(jit_context_t *ctx, int wasi_fd) {
    if (!ctx->fd_host_paths || !ctx->fd_is_dir) return NULL;
    if (wasi_fd < 0 || wasi_fd >= ctx->fd_table_size) return NULL;
    if (!ctx->fd_is_dir[wasi_fd]) return NULL;
    return ctx->fd_host_paths[wasi_fd];
}

static int ensure_fd_metadata_arrays(jit_context_t *ctx) {
    if (ctx->fd_host_paths && ctx->fd_is_dir) return 1;
    if (!ctx->fd_table || ctx->fd_table_size <= 0) return 0;
    ctx->fd_host_paths = malloc(ctx->fd_table_size * sizeof(char*));
    ctx->fd_is_dir = malloc(ctx->fd_table_size * sizeof(uint8_t));
    if (!ctx->fd_host_paths || !ctx->fd_is_dir) {
        free(ctx->fd_host_paths);
        free(ctx->fd_is_dir);
        ctx->fd_host_paths = NULL;
        ctx->fd_is_dir = NULL;
        return 0;
    }
    for (int i = 0; i < ctx->fd_table_size; i++) {
        ctx->fd_host_paths[i] = NULL;
        ctx->fd_is_dir[i] = 0;
    }
    return 1;
}

static int ensure_fd_capacity(jit_context_t *ctx, int target_fd) {
    if (!ctx->fd_table || ctx->fd_table_size <= 0) return 0;
    if (target_fd < ctx->fd_table_size) return 1;
    if (!ensure_fd_metadata_arrays(ctx)) return 0;

    int new_size = ctx->fd_table_size;
    while (new_size <= target_fd) {
        new_size *= 2;
    }

    int *new_table = malloc(new_size * sizeof(int));
    char **new_paths = malloc(new_size * sizeof(char*));
    uint8_t *new_is_dir = malloc(new_size * sizeof(uint8_t));
    if (!new_table || !new_paths || !new_is_dir) {
        free(new_table);
        free(new_paths);
        free(new_is_dir);
        return 0;
    }

    memcpy(new_table, ctx->fd_table, ctx->fd_table_size * sizeof(int));
    memcpy(new_paths, ctx->fd_host_paths, ctx->fd_table_size * sizeof(char*));
    memcpy(new_is_dir, ctx->fd_is_dir, ctx->fd_table_size * sizeof(uint8_t));
    for (int i = ctx->fd_table_size; i < new_size; i++) {
        new_table[i] = -1;
        new_paths[i] = NULL;
        new_is_dir[i] = 0;
    }

    free(ctx->fd_table);
    free(ctx->fd_host_paths);
    free(ctx->fd_is_dir);
    ctx->fd_table = new_table;
    ctx->fd_host_paths = new_paths;
    ctx->fd_is_dir = new_is_dir;
    ctx->fd_table_size = new_size;
    return 1;
}

typedef moonbit_bytes_t (*wasi_stdin_callback_fn)(void *closure);

static void clear_wasi_stdin_buffer(jit_context_t *ctx) {
    if (!ctx) return;
    ctx->wasi_stdin_use_buffer = 0;
    if (ctx->wasi_stdin_buf) {
        free(ctx->wasi_stdin_buf);
        ctx->wasi_stdin_buf = NULL;
    }
    ctx->wasi_stdin_len = 0;
    ctx->wasi_stdin_offset = 0;
}

static void clear_wasi_stdin_callback(jit_context_t *ctx) {
    if (!ctx) return;
    if (ctx->wasi_stdin_callback_data) {
        moonbit_decref(ctx->wasi_stdin_callback_data);
        ctx->wasi_stdin_callback_data = NULL;
    }
    ctx->wasi_stdin_callback = NULL;
}

static void clear_fd_metadata(jit_context_t *ctx, int wasi_fd) {
    if (!ctx->fd_host_paths || !ctx->fd_is_dir) return;
    if (wasi_fd < 0 || wasi_fd >= ctx->fd_table_size) return;
    if (ctx->fd_host_paths[wasi_fd]) {
        free(ctx->fd_host_paths[wasi_fd]);
        ctx->fd_host_paths[wasi_fd] = NULL;
    }
    ctx->fd_is_dir[wasi_fd] = 0;
}

static void set_fd_metadata(jit_context_t *ctx, int wasi_fd, char *host_path, int is_dir) {
    if (!host_path) return;
    if (!ctx->fd_host_paths || !ctx->fd_is_dir || wasi_fd < 0 || wasi_fd >= ctx->fd_table_size) {
        free(host_path);
        return;
    }
    clear_fd_metadata(ctx, wasi_fd);
    ctx->fd_host_paths[wasi_fd] = host_path;
    ctx->fd_is_dir[wasi_fd] = is_dir ? 1 : 0;
}

// Normalize guest path and reject attempts to escape preopen root.
static char* sanitize_guest_path(const char *path) {
    if (!path) return NULL;
    if (path[0] == '\0') return strdup("");
    if (path[0] == '/') return NULL;

    size_t len = strlen(path);
    char *scratch = strdup(path);
    if (!scratch) return NULL;
    char **stack = malloc((len + 1) * sizeof(char *));
    if (!stack) {
        free(scratch);
        return NULL;
    }

    size_t sp = 0;
    char *p = scratch;
    while (1) {
        char *seg = p;
        while (*p != '/' && *p != '\0') p++;
        char term = *p;
        *p = '\0';

        if (seg[0] != '\0' && strcmp(seg, ".") != 0) {
            if (strcmp(seg, "..") == 0) {
                if (sp == 0) {
                    free(stack);
                    free(scratch);
                    return NULL;
                }
                sp--;
            } else {
                stack[sp++] = seg;
            }
        }
        if (term == '\0') break;
        p++;
    }

    size_t out_len = 0;
    for (size_t i = 0; i < sp; i++) {
        out_len += strlen(stack[i]);
        if (i > 0) out_len += 1;
    }
    char *out = malloc(out_len + 1);
    if (!out) {
        free(stack);
        free(scratch);
        return NULL;
    }

    char *cursor = out;
    for (size_t i = 0; i < sp; i++) {
        if (i > 0) {
            *cursor++ = '/';
        }
        size_t seg_len = strlen(stack[i]);
        memcpy(cursor, stack[i], seg_len);
        cursor += seg_len;
    }
    *cursor = '\0';

    free(stack);
    free(scratch);
    return out;
}

static int check_mem_range(jit_context_t *ctx, int64_t ptr, size_t len) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return 0;
    if (ptr < 0) return 0;
    size_t mem_len = atomic_load_explicit(&ctx->memory0->current_length, memory_order_relaxed);
    size_t uptr = (size_t)ptr;
    if (uptr > mem_len) return 0;
    if (len > mem_len - uptr) return 0;
    return 1;
}

// Resolve path relative to a directory fd
static char* resolve_path(jit_context_t *ctx, int dir_fd, const char *path) {
    const char *base = get_preopen_path(ctx, dir_fd);
    if (!base) {
        base = get_open_dir_path(ctx, dir_fd);
        if (!base) return NULL;
    }

    char *rel = sanitize_guest_path(path);
    if (!rel) return NULL;
    if (rel[0] == '\0') {
        free(rel);
        return strdup(base);
    }

    size_t base_len = strlen(base);
    size_t rel_len = strlen(rel);
    char *result = malloc(base_len + rel_len + 2);
    if (!result) {
        free(rel);
        return NULL;
    }

    strcpy(result, base);
    if (base_len > 0 && base[base_len - 1] != '/') {
        strcat(result, "/");
    }
    strcat(result, rel);
    free(rel);
    return result;
}

// Allocate a new WASI fd
static int alloc_wasi_fd(jit_context_t *ctx, int native_fd) {
    if (!ctx->fd_table) {
        ctx->fd_table_size = 64;
        ctx->fd_table = malloc(ctx->fd_table_size * sizeof(int));
        if (!ctx->fd_table) return -1;
        for (int i = 0; i < ctx->fd_table_size; i++) {
            ctx->fd_table[i] = -1;
        }
        if (!ensure_fd_metadata_arrays(ctx)) {
            free(ctx->fd_table);
            ctx->fd_table = NULL;
            ctx->fd_table_size = 0;
            return -1;
        }
        ctx->fd_next = 3 + ctx->preopen_count;
    } else if (!ctx->fd_host_paths || !ctx->fd_is_dir) {
        if (!ensure_fd_metadata_arrays(ctx)) return -1;
    }

    // Find next available slot
    for (int i = ctx->fd_next; i < ctx->fd_table_size; i++) {
        if (ctx->fd_table[i] < 0) {
            ctx->fd_table[i] = native_fd;
            clear_fd_metadata(ctx, i);
            ctx->fd_next = i + 1;
            return i;
        }
    }

    // Expand table
    int new_size = ctx->fd_table_size * 2;
    int *new_table = malloc(new_size * sizeof(int));
    char **new_paths = malloc(new_size * sizeof(char*));
    uint8_t *new_is_dir = malloc(new_size * sizeof(uint8_t));
    if (!new_table || !new_paths || !new_is_dir) {
        free(new_table);
        free(new_paths);
        free(new_is_dir);
        return -1;
    }

    memcpy(new_table, ctx->fd_table, ctx->fd_table_size * sizeof(int));
    memcpy(new_paths, ctx->fd_host_paths, ctx->fd_table_size * sizeof(char*));
    memcpy(new_is_dir, ctx->fd_is_dir, ctx->fd_table_size * sizeof(uint8_t));
    for (int i = ctx->fd_table_size; i < new_size; i++) {
        new_table[i] = -1;
        new_paths[i] = NULL;
        new_is_dir[i] = 0;
    }
    free(ctx->fd_table);
    free(ctx->fd_host_paths);
    free(ctx->fd_is_dir);
    ctx->fd_table = new_table;
    ctx->fd_host_paths = new_paths;
    ctx->fd_is_dir = new_is_dir;
    ctx->fd_table_size = new_size;
    int fd = ctx->fd_table_size / 2;
    ctx->fd_table[fd] = native_fd;
    ctx->fd_next = fd + 1;
    return fd;
}

// Convert errno to WASI errno
static int errno_to_wasi(int err) {
    switch (err) {
        case 0: return WASI_ESUCCESS;
        case EACCES: return WASI_EACCES;
        case EBADF: return WASI_EBADF;
        case EEXIST: return WASI_EEXIST;
        case EINVAL: return WASI_EINVAL;
        case EIO: return WASI_EIO;
        case EISDIR: return WASI_EISDIR;
        case ENOENT: return WASI_ENOENT;
        case ENOSYS: return WASI_ENOSYS;
        case ENOTDIR: return WASI_ENOTDIR;
        case ENOTEMPTY: return WASI_ENOTEMPTY;
        case ESPIPE: return WASI_ESPIPE;
        default: return WASI_EIO;
    }
}

static int is_valid_rights(int64_t rights) {
    return (((uint64_t)rights) & ~WASI_RIGHTS_ALL_VALID) == 0;
}

#ifndef _WIN32
static int fill_random_bytes(uint8_t *buf, size_t len) {
#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__)
    arc4random_buf(buf, len);
    return 1;
#elif defined(__linux__)
    ssize_t n = getrandom(buf, len, 0);
    if (n == (ssize_t)len) return 1;
#endif
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) return 0;
    size_t off = 0;
    while (off < len) {
        ssize_t n = read(fd, buf + off, len - off);
        if (n <= 0) {
            close(fd);
            return 0;
        }
        off += (size_t)n;
    }
    close(fd);
    return 1;
}
#else
static int fill_random_bytes(uint8_t *buf, size_t len) {
    if (len == 0) return 1;
    NTSTATUS status = BCryptGenRandom(
        NULL, buf, (ULONG)len, BCRYPT_USE_SYSTEM_PREFERRED_RNG
    );
    return status == 0;
}
#endif

#ifndef _WIN32
// Convert stat mode to WASI filetype
static uint8_t mode_to_filetype(mode_t mode) {
    if (S_ISREG(mode)) return WASI_FILETYPE_REGULAR_FILE;
    if (S_ISDIR(mode)) return WASI_FILETYPE_DIRECTORY;
    if (S_ISCHR(mode)) return WASI_FILETYPE_CHARACTER_DEVICE;
    if (S_ISBLK(mode)) return WASI_FILETYPE_BLOCK_DEVICE;
    if (S_ISLNK(mode)) return WASI_FILETYPE_SYMBOLIC_LINK;
    if (S_ISSOCK(mode)) return WASI_FILETYPE_SOCKET_STREAM;
    return WASI_FILETYPE_UNKNOWN;
}
#endif

static int append_output_buffer(
    uint8_t **buf,
    size_t *len,
    size_t *cap,
    const uint8_t *data,
    size_t data_len
) {
    if (data_len == 0) return 1;
    size_t needed = *len + data_len;
    if (needed > *cap) {
        size_t new_cap = *cap == 0 ? 256 : *cap;
        while (new_cap < needed) {
            new_cap *= 2;
        }
        uint8_t *new_buf = realloc(*buf, new_cap);
        if (!new_buf) return 0;
        *buf = new_buf;
        *cap = new_cap;
    }
    memcpy(*buf + *len, data, data_len);
    *len += data_len;
    return 1;
}

// ============ WASI Trampolines ============
// JIT ABI: X0 = vmctx, X1.. = WASM arguments.

// fd_write: (fd, iovs, iovs_len, nwritten) -> errno
static int64_t wasi_fd_write_impl(
    jit_context_t *ctx,
    int64_t fd, int64_t iovs, int64_t iovs_len, int64_t nwritten_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;

    uint8_t *mem = ctx->memory0->base;
    int wasi_fd = (int)fd;
    if (wasi_fd == 0) return WASI_EBADF;
    int use_stdout_capture = (wasi_fd == 1 && ctx->wasi_stdout_capture);
    int use_stderr_capture = (wasi_fd == 2 && ctx->wasi_stderr_capture);
    int native_fd = -1;
    if (!use_stdout_capture && !use_stderr_capture) {
        native_fd = get_native_fd(ctx, wasi_fd);
        if (native_fd < 0) return WASI_EBADF;
    }
    uint32_t iovs_u = (uint32_t)iovs;
    uint32_t iovs_len_u = (uint32_t)iovs_len;
    uint32_t nwritten_ptr_u = (uint32_t)nwritten_ptr;
    if (!check_mem_range(ctx, iovs_u, (size_t)iovs_len_u * 8)) return WASI_EFAULT;
    if (!check_mem_range(ctx, nwritten_ptr_u, 4)) return WASI_EFAULT;

    uint32_t total = 0;
    for (uint32_t i = 0; i < iovs_len_u; i++) {
        uint32_t buf_ptr = *(uint32_t *)(mem + iovs_u + i * 8);
        uint32_t buf_len = *(uint32_t *)(mem + iovs_u + i * 8 + 4);
        if (buf_len > 0) {
            if (!check_mem_range(ctx, buf_ptr, (size_t)buf_len)) return WASI_EFAULT;
            if (use_stdout_capture) {
                if (!append_output_buffer(
                        &ctx->wasi_stdout_buf,
                        &ctx->wasi_stdout_len,
                        &ctx->wasi_stdout_cap,
                        mem + buf_ptr,
                        (size_t)buf_len
                    )) {
                    return WASI_ENOMEM;
                }
                total += buf_len;
            } else if (use_stderr_capture) {
                if (!append_output_buffer(
                        &ctx->wasi_stderr_buf,
                        &ctx->wasi_stderr_len,
                        &ctx->wasi_stderr_cap,
                        mem + buf_ptr,
                        (size_t)buf_len
                    )) {
                    return WASI_ENOMEM;
                }
                total += buf_len;
            } else {
#ifdef _WIN32
                int n = _write(native_fd, mem + buf_ptr, buf_len);
#else
                ssize_t n = write(native_fd, mem + buf_ptr, buf_len);
#endif
                if (n < 0) return errno_to_wasi(errno);
                total += (uint32_t)n;
            }
        }
    }

    *(uint32_t *)(mem + nwritten_ptr_u) = total;
    return WASI_ESUCCESS;
}

// fd_read: (fd, iovs, iovs_len, nread) -> errno
static int64_t wasi_fd_read_impl(
    jit_context_t *ctx,
    int64_t fd, int64_t iovs, int64_t iovs_len, int64_t nread_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;

    uint8_t *mem = ctx->memory0->base;
    int wasi_fd = (int)fd;
    if (wasi_fd == 1 || wasi_fd == 2) return WASI_EBADF;
    uint32_t iovs_u = (uint32_t)iovs;
    uint32_t iovs_len_u = (uint32_t)iovs_len;
    uint32_t nread_ptr_u = (uint32_t)nread_ptr;
    if (!check_mem_range(ctx, iovs_u, (size_t)iovs_len_u * 8)) return WASI_EFAULT;
    if (!check_mem_range(ctx, nread_ptr_u, 4)) return WASI_EFAULT;

    uint32_t total = 0;
    if (wasi_fd == 0) {
        if (ctx->wasi_stdin_use_buffer) {
            size_t available = 0;
            if (ctx->wasi_stdin_len > ctx->wasi_stdin_offset) {
                available = ctx->wasi_stdin_len - ctx->wasi_stdin_offset;
            }
            for (uint32_t i = 0; i < iovs_len_u && available > 0; i++) {
                uint32_t buf_ptr = *(uint32_t *)(mem + iovs_u + i * 8);
                uint32_t buf_len = *(uint32_t *)(mem + iovs_u + i * 8 + 4);
                if (buf_len > 0) {
                    if (!check_mem_range(ctx, buf_ptr, (size_t)buf_len)) return WASI_EFAULT;
                    size_t to_copy = available < (size_t)buf_len ? available : (size_t)buf_len;
                    if (to_copy > 0 && ctx->wasi_stdin_buf) {
                        memcpy(
                            mem + buf_ptr,
                            ctx->wasi_stdin_buf + ctx->wasi_stdin_offset,
                            to_copy
                        );
                    }
                    ctx->wasi_stdin_offset += to_copy;
                    available -= to_copy;
                    total += (uint32_t)to_copy;
                }
            }
            *(uint32_t *)(mem + nread_ptr_u) = total;
            return WASI_ESUCCESS;
        }
        if (ctx->wasi_stdin_callback) {
            wasi_stdin_callback_fn cb = (wasi_stdin_callback_fn)ctx->wasi_stdin_callback;
            moonbit_bytes_t input = cb(ctx->wasi_stdin_callback_data);
            size_t input_len = 0;
            if (input) {
                input_len = (size_t)Moonbit_array_length(input);
            }
            size_t input_offset = 0;
            for (uint32_t i = 0; i < iovs_len_u && input_offset < input_len; i++) {
                uint32_t buf_ptr = *(uint32_t *)(mem + iovs_u + i * 8);
                uint32_t buf_len = *(uint32_t *)(mem + iovs_u + i * 8 + 4);
                if (buf_len > 0) {
                    if (!check_mem_range(ctx, buf_ptr, (size_t)buf_len)) {
                        if (input) moonbit_decref(input);
                        return WASI_EFAULT;
                    }
                    size_t remaining = input_len - input_offset;
                    size_t to_copy = remaining < (size_t)buf_len ? remaining : (size_t)buf_len;
                    if (to_copy > 0 && input) {
                        memcpy(mem + buf_ptr, input + input_offset, to_copy);
                    }
                    input_offset += to_copy;
                    total += (uint32_t)to_copy;
                }
            }
            *(uint32_t *)(mem + nread_ptr_u) = total;
            if (input) moonbit_decref(input);
            return WASI_ESUCCESS;
        }
    }

    int native_fd = get_native_fd(ctx, wasi_fd);
    if (native_fd < 0) return WASI_EBADF;
    for (uint32_t i = 0; i < iovs_len_u; i++) {
        uint32_t buf_ptr = *(uint32_t *)(mem + iovs_u + i * 8);
        uint32_t buf_len = *(uint32_t *)(mem + iovs_u + i * 8 + 4);
        if (buf_len > 0) {
            if (!check_mem_range(ctx, buf_ptr, (size_t)buf_len)) return WASI_EFAULT;
#ifdef _WIN32
            int n = _read(native_fd, mem + buf_ptr, buf_len);
#else
            ssize_t n = read(native_fd, mem + buf_ptr, buf_len);
#endif
            if (n < 0) return errno_to_wasi(errno);
            total += (uint32_t)n;
            if (n < buf_len) break; // EOF or partial read
        }
    }

    *(uint32_t *)(mem + nread_ptr_u) = total;
    return WASI_ESUCCESS;
}

// fd_close: (fd) -> errno
static int64_t wasi_fd_close_impl(
    jit_context_t *ctx, int64_t fd
) {
    if (!ctx) return WASI_EBADF;

    int wasi_fd = (int)fd;
    if (wasi_fd < 3) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, wasi_fd);
    if (native_fd < 0) return WASI_EBADF;

#ifdef _WIN32
    _close(native_fd);
#else
    close(native_fd);
#endif
    ctx->fd_table[wasi_fd] = -1;
    clear_fd_metadata(ctx, wasi_fd);
    return WASI_ESUCCESS;
}

// fd_seek: (fd, offset, whence, newoffset) -> errno
static int64_t wasi_fd_seek_impl(
    jit_context_t *ctx,
    int64_t fd, int64_t offset, int64_t whence, int64_t newoffset_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;

    int wasi_fd = (int)fd;
    if (wasi_fd < 0) return WASI_EBADF;
    if (wasi_fd < 3) return WASI_ESPIPE; // stdio not seekable
    int native_fd = get_native_fd(ctx, wasi_fd);
    if (native_fd < 0) return WASI_EBADF;
    uint32_t newoffset_ptr_u = (uint32_t)newoffset_ptr;
    if (!check_mem_range(ctx, newoffset_ptr_u, 8)) return WASI_EFAULT;
    uint32_t whence_u = (uint32_t)whence;
    if (whence_u > 2) return WASI_EINVAL;

#ifdef _WIN32
    int64_t pos = _lseeki64(native_fd, offset, (int)whence_u);
#else
    off_t pos = lseek(native_fd, offset, (int)whence_u);
#endif
    if (pos < 0) return errno_to_wasi(errno);

    *(int64_t *)(ctx->memory0->base + newoffset_ptr_u) = pos;
    return WASI_ESUCCESS;
}

// fd_tell: (fd, offset) -> errno
static int64_t wasi_fd_tell_impl(
    jit_context_t *ctx,
    int64_t fd, int64_t offset_ptr
) {
    return wasi_fd_seek_impl(ctx, fd, 0, 1 /* SEEK_CUR */, offset_ptr);
}

// fd_sync: (fd) -> errno
static int64_t wasi_fd_sync_impl(
    jit_context_t *ctx, int64_t fd
) {
    if (!ctx) return WASI_EBADF;

    // stdio fds - no-op, return success
    if (fd >= 0 && fd < 3) return WASI_ESUCCESS;

    int native_fd = get_native_fd(ctx, (int)fd);
    if (native_fd < 0) return WASI_EBADF;

#ifdef _WIN32
    return WASI_ESUCCESS; // No sync on Windows
#else
    if (fsync(native_fd) < 0) return WASI_EIO;
    return WASI_ESUCCESS;
#endif
}

// fd_datasync: (fd) -> errno
static int64_t wasi_fd_datasync_impl(
    jit_context_t *ctx, int64_t fd
) {
    if (!ctx) return WASI_EBADF;

    // stdio fds - no-op, return success
    if (fd >= 0 && fd < 3) return WASI_ESUCCESS;

    int native_fd = get_native_fd(ctx, (int)fd);
    if (native_fd < 0) return WASI_EBADF;

#ifdef _WIN32
    return WASI_ESUCCESS;
#elif defined(__APPLE__)
    if (fsync(native_fd) < 0) return WASI_EIO;
    return WASI_ESUCCESS;
#else
    if (fdatasync(native_fd) < 0) return WASI_EIO;
    return WASI_ESUCCESS;
#endif
}

// fd_fdstat_get: (fd, fdstat) -> errno
static int64_t wasi_fd_fdstat_get_impl(
    jit_context_t *ctx,
    int64_t fd, int64_t fdstat_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t fdstat_ptr_u = (uint32_t)fdstat_ptr;
    if (!check_mem_range(ctx, fdstat_ptr_u, 24)) return WASI_EFAULT;

    uint8_t *mem = ctx->memory0->base;
    int wasi_fd = (int)fd;

    // Determine file type
    uint8_t filetype;
    uint16_t flags = 0;
    if (wasi_fd < 3) {
        filetype = WASI_FILETYPE_CHARACTER_DEVICE;
        // Match interpreter: stdout/stderr are append-capable.
        if (wasi_fd == 1 || wasi_fd == 2) flags = 1;
    } else if (is_preopen_fd(ctx, wasi_fd)) {
        filetype = WASI_FILETYPE_DIRECTORY;
    } else {
        int native_fd = get_native_fd(ctx, wasi_fd);
        if (native_fd < 0) return WASI_EBADF;
#ifndef _WIN32
        struct stat st;
        if (fstat(native_fd, &st) < 0) return errno_to_wasi(errno);
        filetype = mode_to_filetype(st.st_mode);
#else
        filetype = WASI_FILETYPE_REGULAR_FILE;
#endif
    }

    // fdstat: filetype(1) + pad(1) + flags(2) + pad(4) + rights_base(8) + rights_inheriting(8)
    mem[fdstat_ptr_u] = filetype;
    mem[fdstat_ptr_u + 1] = 0;
    *(uint16_t *)(mem + fdstat_ptr_u + 2) = flags;
    *(uint32_t *)(mem + fdstat_ptr_u + 4) = 0;
    *(uint64_t *)(mem + fdstat_ptr_u + 8) = 0x1FFFFFFFULL; // all rights
    *(uint64_t *)(mem + fdstat_ptr_u + 16) = 0x1FFFFFFFULL;
    return WASI_ESUCCESS;
}

// fd_prestat_get: (fd, prestat) -> errno
static int64_t wasi_fd_prestat_get_impl(
    jit_context_t *ctx,
    int64_t fd, int64_t prestat_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t prestat_ptr_u = (uint32_t)prestat_ptr;
    if (!check_mem_range(ctx, prestat_ptr_u, 8)) return WASI_EFAULT;

    int wasi_fd = (int)fd;
    if (!is_preopen_fd(ctx, wasi_fd)) return WASI_EBADF;

    int idx = wasi_fd - ctx->preopen_base_fd;
    const char *guest_path = ctx->preopen_guest_paths[idx];
    size_t len = strlen(guest_path);

    uint8_t *mem = ctx->memory0->base;
    mem[prestat_ptr_u] = 0; // tag = dir
    mem[prestat_ptr_u + 1] = 0;
    mem[prestat_ptr_u + 2] = 0;
    mem[prestat_ptr_u + 3] = 0;
    *(uint32_t *)(mem + prestat_ptr_u + 4) = (uint32_t)len;
    return WASI_ESUCCESS;
}

// fd_prestat_dir_name: (fd, path, path_len) -> errno
static int64_t wasi_fd_prestat_dir_name_impl(
    jit_context_t *ctx,
    int64_t fd, int64_t path_ptr, int64_t path_len
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t path_ptr_u = (uint32_t)path_ptr;
    uint32_t path_len_u = (uint32_t)path_len;
    if (!check_mem_range(ctx, path_ptr_u, (size_t)path_len_u)) return WASI_EFAULT;

    int wasi_fd = (int)fd;
    if (!is_preopen_fd(ctx, wasi_fd)) return WASI_EBADF;

    int idx = wasi_fd - ctx->preopen_base_fd;
    const char *guest_path = ctx->preopen_guest_paths[idx];
    size_t len = strlen(guest_path);
    if ((size_t)path_len_u < len) return WASI_ENAMETOOLONG;
    size_t to_copy = (size_t)path_len_u < len ? (size_t)path_len_u : len;

    memcpy(ctx->memory0->base + path_ptr_u, guest_path, to_copy);
    return WASI_ESUCCESS;
}

// path_open: (fd, dirflags, path, path_len, oflags, rights_base, rights_inh, fdflags, opened_fd) -> errno
static int64_t wasi_path_open_impl(
    jit_context_t *ctx,
    int64_t dir_fd, int64_t dirflags,
    int64_t path_ptr, int64_t path_len,
    int64_t oflags, int64_t rights_base, int64_t rights_inh,
    int64_t fdflags, int64_t opened_fd_ptr
) {
    (void)dirflags;

    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    if (!is_valid_rights(rights_base) || !is_valid_rights(rights_inh)) {
        return WASI_EINVAL;
    }
    uint32_t path_ptr_u = (uint32_t)path_ptr;
    uint32_t path_len_u = (uint32_t)path_len;
    uint32_t opened_fd_ptr_u = (uint32_t)opened_fd_ptr;
    if (!check_mem_range(ctx, path_ptr_u, (size_t)path_len_u)) {
        return WASI_EFAULT;
    }
    if (!check_mem_range(ctx, opened_fd_ptr_u, 4)) return WASI_EFAULT;

    // Read path from memory
    char *path = malloc((size_t)path_len_u + 1);
    if (!path) return WASI_EIO;
    memcpy(path, ctx->memory0->base + path_ptr_u, (size_t)path_len_u);
    path[path_len_u] = '\0';

    // Resolve full path
    char *full_path = resolve_path(ctx, (int)dir_fd, path);
    free(path);
    if (!full_path) return WASI_EBADF;

#ifndef _WIN32
    // Build open flags
    int flags = 0;
    if (oflags & 0x01) flags |= O_CREAT;
    if (oflags & 0x02) flags |= O_DIRECTORY;
    if (oflags & 0x04) flags |= O_EXCL;
    if (oflags & 0x08) flags |= O_TRUNC;
    if (fdflags & 0x01) flags |= O_APPEND;
    if (flags == 0 || (oflags & 0x02)) flags |= O_RDONLY;
    else flags |= O_RDWR;

    int native_fd = open(full_path, flags, 0644);
    if (native_fd < 0) {
        free(full_path);
        return errno_to_wasi(errno);
    }

    int wasi_fd = alloc_wasi_fd(ctx, native_fd);
    if (wasi_fd < 0) {
        close(native_fd);
        free(full_path);
        return WASI_EIO;
    }

    set_fd_metadata(ctx, wasi_fd, full_path, (oflags & 0x02) != 0);
    *(uint32_t *)(ctx->memory0->base + opened_fd_ptr_u) = (uint32_t)wasi_fd;
    return WASI_ESUCCESS;
#else
    free(full_path);
    return WASI_ENOSYS;
#endif
}

// path_unlink_file: (fd, path, path_len) -> errno
static int64_t wasi_path_unlink_file_impl(
    jit_context_t *ctx,
    int64_t dir_fd, int64_t path_ptr, int64_t path_len
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t path_ptr_u = (uint32_t)path_ptr;
    uint32_t path_len_u = (uint32_t)path_len;
    if (!check_mem_range(ctx, path_ptr_u, (size_t)path_len_u)) {
        return WASI_EFAULT;
    }

    char *path = malloc((size_t)path_len_u + 1);
    if (!path) return WASI_EIO;
    memcpy(path, ctx->memory0->base + path_ptr_u, (size_t)path_len_u);
    path[path_len_u] = '\0';

    char *full_path = resolve_path(ctx, (int)dir_fd, path);
    free(path);
    if (!full_path) return WASI_EBADF;

#ifndef _WIN32
    int ret = unlink(full_path);
    free(full_path);
    if (ret < 0) return errno_to_wasi(errno);
    return WASI_ESUCCESS;
#else
    free(full_path);
    return WASI_ENOSYS;
#endif
}

// path_remove_directory: (fd, path, path_len) -> errno
static int64_t wasi_path_remove_directory_impl(
    jit_context_t *ctx,
    int64_t dir_fd, int64_t path_ptr, int64_t path_len
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t path_ptr_u = (uint32_t)path_ptr;
    uint32_t path_len_u = (uint32_t)path_len;
    if (!check_mem_range(ctx, path_ptr_u, (size_t)path_len_u)) {
        return WASI_EFAULT;
    }

    char *path = malloc((size_t)path_len_u + 1);
    if (!path) return WASI_EIO;
    memcpy(path, ctx->memory0->base + path_ptr_u, (size_t)path_len_u);
    path[path_len_u] = '\0';

    char *full_path = resolve_path(ctx, (int)dir_fd, path);
    free(path);
    if (!full_path) return WASI_EBADF;

#ifndef _WIN32
    int ret = rmdir(full_path);
    free(full_path);
    if (ret < 0) return errno_to_wasi(errno);
    return WASI_ESUCCESS;
#else
    free(full_path);
    return WASI_ENOSYS;
#endif
}

// path_create_directory: (fd, path, path_len) -> errno
static int64_t wasi_path_create_directory_impl(
    jit_context_t *ctx,
    int64_t dir_fd, int64_t path_ptr, int64_t path_len
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t path_ptr_u = (uint32_t)path_ptr;
    uint32_t path_len_u = (uint32_t)path_len;
    if (!check_mem_range(ctx, path_ptr_u, (size_t)path_len_u)) {
        return WASI_EFAULT;
    }

    char *path = malloc((size_t)path_len_u + 1);
    if (!path) return WASI_EIO;
    memcpy(path, ctx->memory0->base + path_ptr_u, (size_t)path_len_u);
    path[path_len_u] = '\0';

    char *full_path = resolve_path(ctx, (int)dir_fd, path);
    free(path);
    if (!full_path) return WASI_EBADF;

#ifndef _WIN32
    int ret = mkdir(full_path, 0755);
    free(full_path);
    if (ret < 0) return errno_to_wasi(errno);
    return WASI_ESUCCESS;
#else
    free(full_path);
    return WASI_ENOSYS;
#endif
}

// path_rename: (old_fd, old_path, old_path_len, new_fd, new_path, new_path_len) -> errno
static int64_t wasi_path_rename_impl(
    jit_context_t *ctx,
    int64_t old_fd, int64_t old_path_ptr, int64_t old_path_len,
    int64_t new_fd, int64_t new_path_ptr, int64_t new_path_len
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t old_path_ptr_u = (uint32_t)old_path_ptr;
    uint32_t old_path_len_u = (uint32_t)old_path_len;
    uint32_t new_path_ptr_u = (uint32_t)new_path_ptr;
    uint32_t new_path_len_u = (uint32_t)new_path_len;
    if (!check_mem_range(ctx, old_path_ptr_u, (size_t)old_path_len_u)) {
        return WASI_EFAULT;
    }
    if (!check_mem_range(ctx, new_path_ptr_u, (size_t)new_path_len_u)) {
        return WASI_EFAULT;
    }

    char *old_path = malloc((size_t)old_path_len_u + 1);
    char *new_path = malloc((size_t)new_path_len_u + 1);
    if (!old_path || !new_path) {
        free(old_path);
        free(new_path);
        return WASI_EIO;
    }

    memcpy(old_path, ctx->memory0->base + old_path_ptr_u, (size_t)old_path_len_u);
    old_path[old_path_len_u] = '\0';
    memcpy(new_path, ctx->memory0->base + new_path_ptr_u, (size_t)new_path_len_u);
    new_path[new_path_len_u] = '\0';

    char *old_full = resolve_path(ctx, (int)old_fd, old_path);
    char *new_full = resolve_path(ctx, (int)new_fd, new_path);
    free(old_path);
    free(new_path);

    if (!old_full || !new_full) {
        free(old_full);
        free(new_full);
        return WASI_EBADF;
    }

#ifndef _WIN32
    int ret = rename(old_full, new_full);
    free(old_full);
    free(new_full);
    if (ret < 0) return errno_to_wasi(errno);
    return WASI_ESUCCESS;
#else
    free(old_full);
    free(new_full);
    return WASI_ENOSYS;
#endif
}

// fd_filestat_get: (fd, buf) -> errno
static int64_t wasi_fd_filestat_get_impl(
    jit_context_t *ctx,
    int64_t fd, int64_t buf_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t buf_ptr_u = (uint32_t)buf_ptr;
    if (!check_mem_range(ctx, buf_ptr_u, 64)) return WASI_EFAULT;

    uint8_t *mem = ctx->memory0->base;
    int wasi_fd = (int)fd;

    // Handle stdio
    if (wasi_fd < 3) {
        memset(mem + buf_ptr_u, 0, 64);
        mem[buf_ptr_u + 16] = WASI_FILETYPE_CHARACTER_DEVICE;
        *(uint64_t *)(mem + buf_ptr_u + 24) = 1; // nlink
        return WASI_ESUCCESS;
    }

    // Handle preopens
    if (is_preopen_fd(ctx, wasi_fd)) {
        memset(mem + buf_ptr_u, 0, 64);
        mem[buf_ptr_u + 16] = WASI_FILETYPE_DIRECTORY;
        *(uint64_t *)(mem + buf_ptr_u + 24) = 1;
        return WASI_ESUCCESS;
    }

#ifndef _WIN32
    int native_fd = get_native_fd(ctx, wasi_fd);
    if (native_fd < 0) return WASI_EBADF;

    struct stat st;
    if (fstat(native_fd, &st) < 0) return errno_to_wasi(errno);

    *(uint64_t *)(mem + buf_ptr_u) = st.st_dev;
    *(uint64_t *)(mem + buf_ptr_u + 8) = st.st_ino;
    mem[buf_ptr_u + 16] = mode_to_filetype(st.st_mode);
    memset(mem + buf_ptr_u + 17, 0, 7);
    *(uint64_t *)(mem + buf_ptr_u + 24) = st.st_nlink;
    *(uint64_t *)(mem + buf_ptr_u + 32) = st.st_size;
#ifdef __APPLE__
    *(uint64_t *)(mem + buf_ptr_u + 40) = st.st_atimespec.tv_sec * 1000000000ULL + st.st_atimespec.tv_nsec;
    *(uint64_t *)(mem + buf_ptr_u + 48) = st.st_mtimespec.tv_sec * 1000000000ULL + st.st_mtimespec.tv_nsec;
    *(uint64_t *)(mem + buf_ptr_u + 56) = st.st_ctimespec.tv_sec * 1000000000ULL + st.st_ctimespec.tv_nsec;
#else
    *(uint64_t *)(mem + buf_ptr_u + 40) = st.st_atim.tv_sec * 1000000000ULL + st.st_atim.tv_nsec;
    *(uint64_t *)(mem + buf_ptr_u + 48) = st.st_mtim.tv_sec * 1000000000ULL + st.st_mtim.tv_nsec;
    *(uint64_t *)(mem + buf_ptr_u + 56) = st.st_ctim.tv_sec * 1000000000ULL + st.st_ctim.tv_nsec;
#endif
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// fd_filestat_set_size: (fd, size) -> errno
static int64_t wasi_fd_filestat_set_size_impl(
    jit_context_t *ctx,
    int64_t fd, int64_t size
) {
    if (!ctx) return WASI_EBADF;

    // stdio fds don't support truncation
    if (fd >= 0 && fd < 3) return WASI_EINVAL;

    int native_fd = get_native_fd(ctx, (int)fd);
    if (native_fd < 0) return WASI_EBADF;

#ifndef _WIN32
    if (ftruncate(native_fd, size) < 0) return WASI_EIO;
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// args_sizes_get: (argc, argv_buf_size) -> errno
static int64_t wasi_args_sizes_get_impl(
    jit_context_t *ctx,
    int64_t argc_ptr, int64_t argv_buf_size_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t argc_ptr_u = (uint32_t)argc_ptr;
    uint32_t argv_buf_size_ptr_u = (uint32_t)argv_buf_size_ptr;
    if (!check_mem_range(ctx, argc_ptr_u, 4)) return WASI_EFAULT;
    if (!check_mem_range(ctx, argv_buf_size_ptr_u, 4)) return WASI_EFAULT;

    uint8_t *mem = ctx->memory0->base;
    int argc = ctx->argc;
    char **args = ctx->args;

    size_t buf_size = 0;
    for (int i = 0; i < argc; i++) {
        buf_size += strlen(args[i]) + 1;
    }

    *(uint32_t *)(mem + argc_ptr_u) = (uint32_t)argc;
    *(uint32_t *)(mem + argv_buf_size_ptr_u) = (uint32_t)buf_size;
    return WASI_ESUCCESS;
}

// args_get: (argv, argv_buf) -> errno
static int64_t wasi_args_get_impl(
    jit_context_t *ctx,
    int64_t argv_ptr, int64_t argv_buf_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t argv_ptr_u = (uint32_t)argv_ptr;
    uint32_t argv_buf_ptr_u = (uint32_t)argv_buf_ptr;

    uint8_t *mem = ctx->memory0->base;
    int argc = ctx->argc;
    char **args = ctx->args;
    if (argc < 0) return WASI_EFAULT;

    size_t buf_size = 0;
    for (int i = 0; i < argc; i++) {
        size_t len = strlen(args[i]) + 1;
        if (buf_size > SIZE_MAX - len) return WASI_EFAULT;
        buf_size += len;
    }
    if (!check_mem_range(ctx, argv_ptr_u, (size_t)argc * 4)) return WASI_EFAULT;
    if (!check_mem_range(ctx, argv_buf_ptr_u, buf_size)) return WASI_EFAULT;

    uint32_t buf_offset = argv_buf_ptr_u;
    for (int i = 0; i < argc; i++) {
        *(uint32_t *)(mem + argv_ptr_u + i * 4) = buf_offset;
        size_t len = strlen(args[i]) + 1;
        memcpy(mem + buf_offset, args[i], len);
        buf_offset += (uint32_t)len;
    }
    return WASI_ESUCCESS;
}

// environ_sizes_get: (environc, environ_buf_size) -> errno
static int64_t wasi_environ_sizes_get_impl(
    jit_context_t *ctx,
    int64_t environc_ptr, int64_t environ_buf_size_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t environc_ptr_u = (uint32_t)environc_ptr;
    uint32_t environ_buf_size_ptr_u = (uint32_t)environ_buf_size_ptr;
    if (!check_mem_range(ctx, environc_ptr_u, 4)) return WASI_EFAULT;
    if (!check_mem_range(ctx, environ_buf_size_ptr_u, 4)) return WASI_EFAULT;

    uint8_t *mem = ctx->memory0->base;
    int envc = ctx->envc;
    char **envp = ctx->envp;

    size_t buf_size = 0;
    for (int i = 0; i < envc; i++) {
        buf_size += strlen(envp[i]) + 1;
    }

    *(uint32_t *)(mem + environc_ptr_u) = (uint32_t)envc;
    *(uint32_t *)(mem + environ_buf_size_ptr_u) = (uint32_t)buf_size;
    return WASI_ESUCCESS;
}

// environ_get: (environ, environ_buf) -> errno
static int64_t wasi_environ_get_impl(
    jit_context_t *ctx,
    int64_t environ_ptr, int64_t environ_buf_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t environ_ptr_u = (uint32_t)environ_ptr;
    uint32_t environ_buf_ptr_u = (uint32_t)environ_buf_ptr;

    uint8_t *mem = ctx->memory0->base;
    int envc = ctx->envc;
    char **envp = ctx->envp;
    if (envc < 0) return WASI_EFAULT;

    size_t buf_size = 0;
    for (int i = 0; i < envc; i++) {
        size_t len = strlen(envp[i]) + 1;
        if (buf_size > SIZE_MAX - len) return WASI_EFAULT;
        buf_size += len;
    }
    if (!check_mem_range(ctx, environ_ptr_u, (size_t)envc * 4)) return WASI_EFAULT;
    if (!check_mem_range(ctx, environ_buf_ptr_u, buf_size)) return WASI_EFAULT;

    uint32_t buf_offset = environ_buf_ptr_u;
    for (int i = 0; i < envc; i++) {
        *(uint32_t *)(mem + environ_ptr_u + i * 4) = buf_offset;
        size_t len = strlen(envp[i]) + 1;
        memcpy(mem + buf_offset, envp[i], len);
        buf_offset += (uint32_t)len;
    }
    return WASI_ESUCCESS;
}

// clock_time_get: (clock_id, precision, time) -> errno
static int64_t wasi_clock_time_get_impl(
    jit_context_t *ctx,
    int64_t clock_id, int64_t precision, int64_t time_ptr
) {
    (void)precision;
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t time_ptr_u = (uint32_t)time_ptr;
    if (!check_mem_range(ctx, time_ptr_u, 8)) return WASI_EFAULT;

    int64_t time_ns = 0;
    // WASI clock IDs: 0=REALTIME, 1=MONOTONIC, 2=PROCESS_CPUTIME_ID, 3=THREAD_CPUTIME_ID
    if (clock_id >= 0 && clock_id <= 3) {
#ifdef _WIN32
        FILETIME ft;
        GetSystemTimeAsFileTime(&ft);
        uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
        time_ns = (int64_t)((t - 116444736000000000ULL) * 100);
#else
        // For CPU time clocks (2 and 3), fall back to monotonic clock
        // since we don't have platform-specific APIs for these yet
        struct timespec ts;
        clockid_t clk = (clock_id == 0) ? CLOCK_REALTIME : CLOCK_MONOTONIC;
        clock_gettime(clk, &ts);
        time_ns = (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
    } else {
        return WASI_EINVAL;
    }

    *(int64_t *)(ctx->memory0->base + time_ptr_u) = time_ns;
    return WASI_ESUCCESS;
}

// clock_res_get: (clock_id, resolution) -> errno
static int64_t wasi_clock_res_get_impl(
    jit_context_t *ctx,
    int64_t clock_id, int64_t resolution_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t resolution_ptr_u = (uint32_t)resolution_ptr;
    if (!check_mem_range(ctx, resolution_ptr_u, 8)) return WASI_EFAULT;

    // WASI clock IDs: 0=REALTIME, 1=MONOTONIC, 2=PROCESS_CPUTIME_ID, 3=THREAD_CPUTIME_ID
    if (clock_id < 0 || clock_id > 3) return WASI_EINVAL;

    *(int64_t *)(ctx->memory0->base + resolution_ptr_u) = 1000000; // 1ms
    return WASI_ESUCCESS;
}

// random_get: (buf, buf_len) -> errno
static int64_t wasi_random_get_impl(
    jit_context_t *ctx,
    int64_t buf_ptr, int64_t buf_len
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t buf_ptr_u = (uint32_t)buf_ptr;
    uint32_t buf_len_u = (uint32_t)buf_len;
    if (!check_mem_range(ctx, buf_ptr_u, (size_t)buf_len_u)) {
        return WASI_EFAULT;
    }

    uint8_t *mem = ctx->memory0->base;
    if (buf_len_u == 0) return WASI_ESUCCESS;
    if (!fill_random_bytes(mem + buf_ptr_u, (size_t)buf_len_u)) return WASI_EIO;
    return WASI_ESUCCESS;
}

// proc_exit: (exit_code) -> noreturn
static int64_t wasi_proc_exit_impl(
    jit_context_t *ctx, int64_t exit_code
) {
    if (!ctx) return 0;
    ctx->wasi_exited = 1;
    ctx->wasi_exit_code = (int)exit_code;
    if (g_trap_active) {
        g_trap_code = WASI_TRAP_EXIT;
        siglongjmp(g_trap_jmp_buf, 1);
    }
    return 0;
}

// proc_raise: (signal) -> errno
static int64_t wasi_proc_raise_impl(
    jit_context_t *ctx, int64_t sig
) {
    (void)ctx;
    if (raise((int)sig) < 0) return errno_to_wasi(errno);
    return WASI_ESUCCESS;
}

// sched_yield: () -> errno
static int64_t wasi_sched_yield_impl(
    jit_context_t *ctx
) {
    (void)ctx;
#ifndef _WIN32
    sched_yield();
#endif
    return WASI_ESUCCESS;
}

// poll_oneoff: (in, out, nsubscriptions, nevents) -> errno
static int64_t wasi_poll_oneoff_impl(
    jit_context_t *ctx,
    int64_t in_ptr, int64_t out_ptr, int64_t nsubscriptions, int64_t nevents_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t in_ptr_u = (uint32_t)in_ptr;
    uint32_t out_ptr_u = (uint32_t)out_ptr;
    uint32_t nevents_ptr_u = (uint32_t)nevents_ptr;
    uint32_t nsubscriptions_u = (uint32_t)nsubscriptions;
    if (!check_mem_range(ctx, in_ptr_u, (size_t)nsubscriptions_u * 48)) return WASI_EFAULT;
    if (!check_mem_range(ctx, out_ptr_u, (size_t)nsubscriptions_u * 32)) return WASI_EFAULT;
    if (!check_mem_range(ctx, nevents_ptr_u, 4)) return WASI_EFAULT;

    uint8_t *mem = ctx->memory0->base;
    if (nsubscriptions_u == 0) {
        *(uint32_t *)(mem + nevents_ptr_u) = 0;
        return WASI_ESUCCESS;
    }

    int64_t min_timeout = -1;
    int num_fds = 0;

    for (uint32_t i = 0; i < nsubscriptions_u; i++) {
        size_t sub = (size_t)in_ptr_u + (size_t)i * 48;
        uint8_t tag = mem[sub + 8];
        if (tag == 0) {
            int64_t timeout = *(int64_t *)(mem + sub + 24);
            uint16_t flags = *(uint16_t *)(mem + sub + 40);
            int64_t timeout_ns;
            if (flags & 1) {
#ifndef _WIN32
                struct timespec ts;
                clock_gettime(CLOCK_MONOTONIC, &ts);
                int64_t now = (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
                timeout_ns = timeout > now ? timeout - now : 0;
#else
                timeout_ns = 0;
#endif
            } else {
                timeout_ns = timeout;
            }
            if (min_timeout < 0 || timeout_ns < min_timeout) {
                min_timeout = timeout_ns;
            }
        } else if (tag == 1 || tag == 2) {
            int32_t fd = *(int32_t *)(mem + sub + 12);
            // Match interpreter: stdio fds are virtual (callbacks/buffers),
            // so poll_oneoff should not block on them.
            if (fd >= 0 && fd <= 2) {
                continue;
            }
            int native_fd = get_native_fd(ctx, fd);
            if (native_fd >= 0) {
                num_fds++;
            }
        }
    }

    int timeout_ms = -1;
    if (min_timeout == 0) {
        timeout_ms = 0;
    } else if (min_timeout > 0) {
        int64_t ms = min_timeout / 1000000LL;
        timeout_ms = (ms == 0) ? 1 : (int)ms;
    }

    uint32_t events_written = 0;
    int clock_ready = 0;

#ifndef _WIN32
    struct pollfd *pfds = NULL;
    int *sub_indices = NULL;
    if (num_fds > 0) {
        pfds = calloc((size_t)num_fds, sizeof(struct pollfd));
        sub_indices = calloc((size_t)num_fds, sizeof(int));
        if (!pfds || !sub_indices) {
            free(pfds);
            free(sub_indices);
            return WASI_ENOMEM;
        }
        int idx = 0;
        for (uint32_t i = 0; i < nsubscriptions_u; i++) {
            size_t sub = (size_t)in_ptr_u + (size_t)i * 48;
            uint8_t tag = mem[sub + 8];
            if (tag == 1 || tag == 2) {
                int32_t fd = *(int32_t *)(mem + sub + 12);
                if (fd >= 0 && fd <= 2) {
                    continue;
                }
                int native_fd = get_native_fd(ctx, fd);
                if (native_fd >= 0) {
                    pfds[idx].fd = native_fd;
                    pfds[idx].events = (tag == 1) ? POLLIN : POLLOUT;
                    sub_indices[idx] = (int)i;
                    idx++;
                }
            }
        }

        int poll_result = poll(pfds, (nfds_t)num_fds, timeout_ms);
        if (poll_result > 0) {
            for (int i = 0; i < num_fds; i++) {
                if (pfds[i].revents != 0 && events_written < nsubscriptions_u) {
                    size_t sub = (size_t)in_ptr_u + (size_t)sub_indices[i] * 48;
                    int64_t userdata = *(int64_t *)(mem + sub);
                    uint8_t tag = mem[sub + 8];
                    size_t evt = (size_t)out_ptr_u + (size_t)events_written * 32;

                    *(int64_t *)(mem + evt) = userdata;
                    *(uint16_t *)(mem + evt + 8) = 0;
                    mem[evt + 10] = tag;
                    memset(mem + evt + 11, 0, 5);
                    *(int64_t *)(mem + evt + 16) = 0;
                    *(uint16_t *)(mem + evt + 24) = 0;
                    memset(mem + evt + 26, 0, 6);
                    events_written++;
                }
            }
        }
        if (poll_result == 0) {
            clock_ready = 1;
        }
        free(pfds);
        free(sub_indices);
    } else if (min_timeout >= 0) {
        struct timespec ts = {
            .tv_sec = min_timeout / 1000000000LL,
            .tv_nsec = min_timeout % 1000000000LL
        };
        nanosleep(&ts, NULL);
        clock_ready = 1;
    }
#else
    (void)timeout_ms;
    if (min_timeout >= 0 && num_fds == 0) {
        clock_ready = 1;
    }
#endif

    if (clock_ready) {
        for (uint32_t i = 0; i < nsubscriptions_u && events_written < nsubscriptions_u; i++) {
            size_t sub = (size_t)in_ptr_u + (size_t)i * 48;
            uint8_t tag = mem[sub + 8];
            if (tag == 0) {
                int64_t userdata = *(int64_t *)(mem + sub);
                size_t evt = (size_t)out_ptr_u + (size_t)events_written * 32;
                *(int64_t *)(mem + evt) = userdata;
                *(uint16_t *)(mem + evt + 8) = 0;
                mem[evt + 10] = 0;
                memset(mem + evt + 11, 0, 21);
                events_written++;
            }
        }
    }

    *(uint32_t *)(mem + nevents_ptr_u) = events_written;
    return WASI_ESUCCESS;
}

// ============ Additional File Operations ============

// fd_pread: Read from fd at offset without changing position
static int32_t wasi_fd_pread_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t iovs_ptr, int32_t iovs_len, int64_t offset, int32_t nread_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint8_t *mem = ctx->memory0->base;
    uint32_t iovs_ptr_u = (uint32_t)iovs_ptr;
    uint32_t iovs_len_u = (uint32_t)iovs_len;
    uint32_t nread_ptr_u = (uint32_t)nread_ptr;
    if (!check_mem_range(ctx, iovs_ptr_u, (size_t)iovs_len_u * 8)) return WASI_EFAULT;
    if (!check_mem_range(ctx, nread_ptr_u, 4)) return WASI_EFAULT;

    // stdio fds are not seekable, so pread is not supported
    if (fd >= 0 && fd < 3) return WASI_ESPIPE;

    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;

#ifndef _WIN32
    size_t total = 0;
    for (uint32_t i = 0; i < iovs_len_u; i++) {
        uint32_t buf_ptr = *(uint32_t *)(mem + iovs_ptr_u + i * 8);
        uint32_t buf_len = *(uint32_t *)(mem + iovs_ptr_u + i * 8 + 4);
        if (buf_len > 0 && !check_mem_range(ctx, buf_ptr, (size_t)buf_len)) {
            return WASI_EFAULT;
        }
        ssize_t n = pread(native_fd, mem + buf_ptr, buf_len, offset + total);
        if (n < 0) return WASI_EIO;
        total += n;
        if (n < buf_len) break;
    }
    *(uint32_t *)(mem + nread_ptr_u) = (uint32_t)total;
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// fd_pwrite: Write to fd at offset without changing position
static int32_t wasi_fd_pwrite_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t iovs_ptr, int32_t iovs_len, int64_t offset, int32_t nwritten_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint8_t *mem = ctx->memory0->base;
    uint32_t iovs_ptr_u = (uint32_t)iovs_ptr;
    uint32_t iovs_len_u = (uint32_t)iovs_len;
    uint32_t nwritten_ptr_u = (uint32_t)nwritten_ptr;
    if (!check_mem_range(ctx, iovs_ptr_u, (size_t)iovs_len_u * 8)) return WASI_EFAULT;
    if (!check_mem_range(ctx, nwritten_ptr_u, 4)) return WASI_EFAULT;

    // stdio fds are not seekable, so pwrite is not supported
    if (fd >= 0 && fd < 3) return WASI_ESPIPE;

    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;

#ifndef _WIN32
    size_t total = 0;
    for (uint32_t i = 0; i < iovs_len_u; i++) {
        uint32_t buf_ptr = *(uint32_t *)(mem + iovs_ptr_u + i * 8);
        uint32_t buf_len = *(uint32_t *)(mem + iovs_ptr_u + i * 8 + 4);
        if (buf_len > 0 && !check_mem_range(ctx, buf_ptr, (size_t)buf_len)) {
            return WASI_EFAULT;
        }
        ssize_t n = pwrite(native_fd, mem + buf_ptr, buf_len, offset + total);
        if (n < 0) return WASI_EIO;
        total += n;
        if (n < buf_len) break;
    }
    *(uint32_t *)(mem + nwritten_ptr_u) = (uint32_t)total;
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// fd_readdir: Read directory entries
static int32_t wasi_fd_readdir_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t buf_ptr, int32_t buf_len, int64_t cookie, int32_t bufused_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    if (fd >= 0 && fd < 3) return WASI_EBADF;
    uint8_t *mem = ctx->memory0->base;
    uint32_t buf_ptr_u = (uint32_t)buf_ptr;
    uint32_t buf_len_u = (uint32_t)buf_len;
    uint32_t bufused_ptr_u = (uint32_t)bufused_ptr;
    if (!check_mem_range(ctx, buf_ptr_u, (size_t)buf_len_u)) return WASI_EFAULT;
    if (!check_mem_range(ctx, bufused_ptr_u, 4)) return WASI_EFAULT;

#ifndef _WIN32
    DIR *dir = NULL;
    int dir_fd = -1;
    if (is_preopen_fd(ctx, fd)) {
        const char *path = get_preopen_path(ctx, fd);
        if (!path) return WASI_EBADF;
        dir = opendir(path);
        if (!dir) return errno_to_wasi(errno);
    } else {
        int native_fd = get_native_fd(ctx, fd);
        if (native_fd < 0) return WASI_EBADF;
        dir_fd = dup(native_fd);
        if (dir_fd < 0) return errno_to_wasi(errno);
        dir = fdopendir(dir_fd);
        if (!dir) {
            close(dir_fd);
            return errno_to_wasi(errno);
        }
    }

    // Skip to cookie position
    int64_t pos = 0;
    struct dirent *entry;
    while (pos < cookie && (entry = readdir(dir)) != NULL) {
        pos++;
    }

    // Read entries into buffer
    uint8_t *buf = mem + buf_ptr_u;
    uint32_t used = 0;

    while ((entry = readdir(dir)) != NULL && used < buf_len_u) {
        size_t name_len = strlen(entry->d_name);
        size_t entry_size = 24 + name_len; // dirent header + name

        if ((size_t)used + entry_size > (size_t)buf_len_u) {
            // Not enough space, but we've read some entries
            break;
        }

        // Write dirent structure
        // d_next: u64 (cookie for next entry)
        *(uint64_t *)(buf + used) = pos + 1;
        // d_ino: u64
        *(uint64_t *)(buf + used + 8) = entry->d_ino;
        // d_namlen: u32
        *(uint32_t *)(buf + used + 16) = (uint32_t)name_len;
        // d_type: u8
        uint8_t wasi_type = WASI_FILETYPE_UNKNOWN;
        switch (entry->d_type) {
            case DT_REG: wasi_type = WASI_FILETYPE_REGULAR_FILE; break;
            case DT_DIR: wasi_type = WASI_FILETYPE_DIRECTORY; break;
            case DT_LNK: wasi_type = WASI_FILETYPE_SYMBOLIC_LINK; break;
            case DT_CHR: wasi_type = WASI_FILETYPE_CHARACTER_DEVICE; break;
            case DT_BLK: wasi_type = WASI_FILETYPE_BLOCK_DEVICE; break;
            case DT_SOCK: wasi_type = WASI_FILETYPE_SOCKET_STREAM; break;
        }
        *(uint8_t *)(buf + used + 20) = wasi_type;
        // Copy name
        memcpy(buf + used + 24, entry->d_name, name_len);

        used += entry_size;
        pos++;
    }

    closedir(dir);
    *(uint32_t *)(mem + bufused_ptr_u) = used;
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// path_filestat_get: Get file stats by path
static int32_t wasi_path_filestat_get_impl(
    jit_context_t *ctx,
    int32_t dir_fd, int32_t flags, int32_t path_ptr, int32_t path_len, int32_t buf_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint8_t *mem = ctx->memory0->base;
    uint32_t path_ptr_u = (uint32_t)path_ptr;
    uint32_t path_len_u = (uint32_t)path_len;
    uint32_t buf_ptr_u = (uint32_t)buf_ptr;
    if (!check_mem_range(ctx, path_ptr_u, (size_t)path_len_u)) return WASI_EFAULT;
    if (!check_mem_range(ctx, buf_ptr_u, 64)) return WASI_EFAULT;

#ifndef _WIN32
    char *path_tmp = malloc((size_t)path_len_u + 1);
    if (!path_tmp) return WASI_EIO;
    memcpy(path_tmp, mem + path_ptr_u, path_len_u);
    path_tmp[path_len_u] = '\0';

    char *full_path = resolve_path(ctx, dir_fd, path_tmp);
    free(path_tmp);
    if (!full_path) return WASI_EBADF;

    struct stat st;
    int result;
    if (flags & 1) { // SYMLINK_FOLLOW
        result = stat(full_path, &st);
    } else {
        result = lstat(full_path, &st);
    }
    free(full_path);
    if (result != 0) return errno_to_wasi(errno);

    // Write filestat structure (64 bytes)
    *(uint64_t *)(mem + buf_ptr_u + 0) = st.st_dev;
    *(uint64_t *)(mem + buf_ptr_u + 8) = st.st_ino;
    *(uint8_t *)(mem + buf_ptr_u + 16) = mode_to_filetype(st.st_mode);
    *(uint64_t *)(mem + buf_ptr_u + 24) = st.st_nlink;
    *(uint64_t *)(mem + buf_ptr_u + 32) = st.st_size;
#ifdef __APPLE__
    *(uint64_t *)(mem + buf_ptr_u + 40) = st.st_atimespec.tv_sec * 1000000000ULL + st.st_atimespec.tv_nsec;
    *(uint64_t *)(mem + buf_ptr_u + 48) = st.st_mtimespec.tv_sec * 1000000000ULL + st.st_mtimespec.tv_nsec;
    *(uint64_t *)(mem + buf_ptr_u + 56) = st.st_ctimespec.tv_sec * 1000000000ULL + st.st_ctimespec.tv_nsec;
#else
    *(uint64_t *)(mem + buf_ptr_u + 40) = st.st_atim.tv_sec * 1000000000ULL + st.st_atim.tv_nsec;
    *(uint64_t *)(mem + buf_ptr_u + 48) = st.st_mtim.tv_sec * 1000000000ULL + st.st_mtim.tv_nsec;
    *(uint64_t *)(mem + buf_ptr_u + 56) = st.st_ctim.tv_sec * 1000000000ULL + st.st_ctim.tv_nsec;
#endif
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// path_readlink: Read symbolic link
static int32_t wasi_path_readlink_impl(
    jit_context_t *ctx,
    int32_t dir_fd, int32_t path_ptr, int32_t path_len,
    int32_t buf_ptr, int32_t buf_len, int32_t bufused_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint8_t *mem = ctx->memory0->base;
    uint32_t path_ptr_u = (uint32_t)path_ptr;
    uint32_t path_len_u = (uint32_t)path_len;
    uint32_t buf_ptr_u = (uint32_t)buf_ptr;
    uint32_t buf_len_u = (uint32_t)buf_len;
    uint32_t bufused_ptr_u = (uint32_t)bufused_ptr;
    if (!check_mem_range(ctx, path_ptr_u, (size_t)path_len_u)) return WASI_EFAULT;
    if (!check_mem_range(ctx, buf_ptr_u, (size_t)buf_len_u)) return WASI_EFAULT;
    if (!check_mem_range(ctx, bufused_ptr_u, 4)) return WASI_EFAULT;

#ifndef _WIN32
    char *path_tmp = malloc((size_t)path_len_u + 1);
    if (!path_tmp) return WASI_EIO;
    memcpy(path_tmp, mem + path_ptr_u, path_len_u);
    path_tmp[path_len_u] = '\0';

    char *full_path = resolve_path(ctx, dir_fd, path_tmp);
    free(path_tmp);
    if (!full_path) return WASI_EBADF;

    ssize_t n = readlink(full_path, (char *)(mem + buf_ptr_u), buf_len_u);
    free(full_path);
    if (n < 0) return errno_to_wasi(errno);

    *(uint32_t *)(mem + bufused_ptr_u) = (uint32_t)n;
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// path_symlink: Create symbolic link
static int32_t wasi_path_symlink_impl(
    jit_context_t *ctx,
    int32_t old_path_ptr, int32_t old_path_len,
    int32_t dir_fd, int32_t new_path_ptr, int32_t new_path_len
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint8_t *mem = ctx->memory0->base;
    uint32_t old_path_ptr_u = (uint32_t)old_path_ptr;
    uint32_t old_path_len_u = (uint32_t)old_path_len;
    uint32_t new_path_ptr_u = (uint32_t)new_path_ptr;
    uint32_t new_path_len_u = (uint32_t)new_path_len;
    if (!check_mem_range(ctx, old_path_ptr_u, (size_t)old_path_len_u)) return WASI_EFAULT;
    if (!check_mem_range(ctx, new_path_ptr_u, (size_t)new_path_len_u)) return WASI_EFAULT;

#ifndef _WIN32
    char *old_path = malloc((size_t)old_path_len_u + 1);
    if (!old_path) return WASI_EIO;
    memcpy(old_path, mem + old_path_ptr_u, old_path_len_u);
    old_path[old_path_len_u] = '\0';

    char *new_path_tmp = malloc((size_t)new_path_len_u + 1);
    if (!new_path_tmp) {
        free(old_path);
        return WASI_EIO;
    }
    memcpy(new_path_tmp, mem + new_path_ptr_u, new_path_len_u);
    new_path_tmp[new_path_len_u] = '\0';

    char *full_new_path = resolve_path(ctx, dir_fd, new_path_tmp);
    free(new_path_tmp);
    if (!full_new_path) {
        free(old_path);
        return WASI_EBADF;
    }

    int result = symlink(old_path, full_new_path);
    free(old_path);
    free(full_new_path);
    if (result != 0) {
        return errno_to_wasi(errno);
    }
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// path_link: Create hard link
static int32_t wasi_path_link_impl(
    jit_context_t *ctx,
    int32_t old_fd, int32_t old_flags,
    int32_t old_path_ptr, int32_t old_path_len,
    int32_t new_fd, int32_t new_path_ptr, int32_t new_path_len
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint8_t *mem = ctx->memory0->base;
    uint32_t old_path_ptr_u = (uint32_t)old_path_ptr;
    uint32_t old_path_len_u = (uint32_t)old_path_len;
    uint32_t new_path_ptr_u = (uint32_t)new_path_ptr;
    uint32_t new_path_len_u = (uint32_t)new_path_len;
    if (!check_mem_range(ctx, old_path_ptr_u, (size_t)old_path_len_u)) return WASI_EFAULT;
    if (!check_mem_range(ctx, new_path_ptr_u, (size_t)new_path_len_u)) return WASI_EFAULT;

#ifndef _WIN32
    char *old_path_tmp = malloc((size_t)old_path_len_u + 1);
    if (!old_path_tmp) return WASI_EIO;
    memcpy(old_path_tmp, mem + old_path_ptr_u, old_path_len_u);
    old_path_tmp[old_path_len_u] = '\0';

    char *new_path_tmp = malloc((size_t)new_path_len_u + 1);
    if (!new_path_tmp) {
        free(old_path_tmp);
        return WASI_EIO;
    }
    memcpy(new_path_tmp, mem + new_path_ptr_u, new_path_len_u);
    new_path_tmp[new_path_len_u] = '\0';

    char *full_old_path = resolve_path(ctx, old_fd, old_path_tmp);
    free(old_path_tmp);
    if (!full_old_path) {
        free(new_path_tmp);
        return WASI_EBADF;
    }

    char *full_new_path = resolve_path(ctx, new_fd, new_path_tmp);
    free(new_path_tmp);
    if (!full_new_path) {
        free(full_old_path);
        return WASI_EBADF;
    }

    int flags = (old_flags & 0x01) ? AT_SYMLINK_FOLLOW : 0;
    int result = linkat(AT_FDCWD, full_old_path, AT_FDCWD, full_new_path, flags);
    free(full_old_path);
    free(full_new_path);
    if (result != 0) {
        return errno_to_wasi(errno);
    }
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// fd_filestat_set_times: Set file timestamps
static int32_t wasi_fd_filestat_set_times_impl(
    jit_context_t *ctx,
    int32_t fd, int64_t atim, int64_t mtim, int32_t fst_flags
) {

    // stdio fds don't support setting timestamps
    if (fd >= 0 && fd < 3) return WASI_EINVAL;

    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;

#ifndef _WIN32
    struct timespec times[2];

    // Access time
    if (fst_flags & 2) { // SET_ATIM_NOW
        times[0].tv_sec = 0;
        times[0].tv_nsec = UTIME_NOW;
    } else if (fst_flags & 1) { // SET_ATIM
        times[0].tv_sec = atim / 1000000000LL;
        times[0].tv_nsec = atim % 1000000000LL;
    } else {
        times[0].tv_sec = 0;
        times[0].tv_nsec = UTIME_OMIT;
    }

    // Modification time
    if (fst_flags & 8) { // SET_MTIM_NOW
        times[1].tv_sec = 0;
        times[1].tv_nsec = UTIME_NOW;
    } else if (fst_flags & 4) { // SET_MTIM
        times[1].tv_sec = mtim / 1000000000LL;
        times[1].tv_nsec = mtim % 1000000000LL;
    } else {
        times[1].tv_sec = 0;
        times[1].tv_nsec = UTIME_OMIT;
    }

    if (futimens(native_fd, times) != 0) {
        return WASI_EIO;
    }
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// path_filestat_set_times: Set file timestamps by path
static int32_t wasi_path_filestat_set_times_impl(
    jit_context_t *ctx,
    int32_t dir_fd, int32_t flags, int32_t path_ptr, int32_t path_len,
    int64_t atim, int64_t mtim, int32_t fst_flags
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint8_t *mem = ctx->memory0->base;
    uint32_t path_ptr_u = (uint32_t)path_ptr;
    uint32_t path_len_u = (uint32_t)path_len;
    if (!check_mem_range(ctx, path_ptr_u, (size_t)path_len_u)) return WASI_EFAULT;

#ifndef _WIN32
    char *path_tmp = malloc((size_t)path_len_u + 1);
    if (!path_tmp) return WASI_EIO;
    memcpy(path_tmp, mem + path_ptr_u, path_len_u);
    path_tmp[path_len_u] = '\0';

    char *full_path = resolve_path(ctx, dir_fd, path_tmp);
    free(path_tmp);
    if (!full_path) return WASI_EBADF;

    struct timespec times[2];

    // Access time
    if (fst_flags & 2) { // SET_ATIM_NOW
        times[0].tv_sec = 0;
        times[0].tv_nsec = UTIME_NOW;
    } else if (fst_flags & 1) { // SET_ATIM
        times[0].tv_sec = atim / 1000000000LL;
        times[0].tv_nsec = atim % 1000000000LL;
    } else {
        times[0].tv_sec = 0;
        times[0].tv_nsec = UTIME_OMIT;
    }

    // Modification time
    if (fst_flags & 8) { // SET_MTIM_NOW
        times[1].tv_sec = 0;
        times[1].tv_nsec = UTIME_NOW;
    } else if (fst_flags & 4) { // SET_MTIM
        times[1].tv_sec = mtim / 1000000000LL;
        times[1].tv_nsec = mtim % 1000000000LL;
    } else {
        times[1].tv_sec = 0;
        times[1].tv_nsec = UTIME_OMIT;
    }

    int at_flags = (flags & 1) ? 0 : AT_SYMLINK_NOFOLLOW;
    int result = utimensat(AT_FDCWD, full_path, times, at_flags);
    free(full_path);
    if (result != 0) {
        return errno_to_wasi(errno);
    }
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// fd_advise: No-op (advice is optional)
static int32_t wasi_fd_advise_impl(
    jit_context_t *ctx,
    int32_t fd, int64_t offset, int64_t len, int32_t advice
) {
    (void)offset;
    (void)len;
    (void)advice;
    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;
    // Advisory only, always succeed
    return WASI_ESUCCESS;
}

// fd_fdstat_set_rights: No-op (rights system simplified)
static int32_t wasi_fd_fdstat_set_rights_impl(
    jit_context_t *ctx,
    int32_t fd, int64_t rights_base, int64_t rights_inheriting
) {
    (void)rights_base;
    (void)rights_inheriting;
    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;
    // Rights system not enforced, always succeed
    return WASI_ESUCCESS;
}

// fd_allocate: Allocate space for a file
static int32_t wasi_fd_allocate_impl(
    jit_context_t *ctx,
    int32_t fd, int64_t offset, int64_t len
) {

    // stdio fds don't support allocation
    if (fd >= 0 && fd < 3) return WASI_EINVAL;

    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;

#ifdef __linux__
    // Linux has posix_fallocate
    int result = posix_fallocate(native_fd, offset, len);
    if (result != 0) return WASI_EIO;
    return WASI_ESUCCESS;
#elif defined(__APPLE__)
    // macOS: use ftruncate as fallback if extending file
    struct stat st;
    if (fstat(native_fd, &st) != 0) return WASI_EIO;
    int64_t new_size = offset + len;
    if (new_size > st.st_size) {
        if (ftruncate(native_fd, new_size) != 0) return WASI_EIO;
    }
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// fd_renumber: Renumber a file descriptor
static int32_t wasi_fd_renumber_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t to_fd
) {
    // Cannot renumber stdio fds
    if ((fd >= 0 && fd < 3) || (to_fd >= 0 && to_fd < 3)) {
        return WASI_EINVAL;
    }

    if (!ctx || !ctx->fd_table) return WASI_EBADF;

    if (!ensure_fd_capacity(ctx, to_fd)) return WASI_EIO;
    if (fd == to_fd) return WASI_ESUCCESS;

    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;

    int native_to_fd = get_native_fd(ctx, to_fd);
    if (native_to_fd >= 0) {
#ifndef _WIN32
        close(native_to_fd);
#endif
    }

#ifndef _WIN32
    ctx->fd_table[to_fd] = native_fd;
    ctx->fd_table[fd] = -1;
    if (ctx->fd_host_paths && ctx->fd_is_dir) {
        clear_fd_metadata(ctx, to_fd);
        ctx->fd_host_paths[to_fd] = ctx->fd_host_paths[fd];
        ctx->fd_is_dir[to_fd] = ctx->fd_is_dir[fd];
        ctx->fd_host_paths[fd] = NULL;
        ctx->fd_is_dir[fd] = 0;
    }
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// fd_fdstat_set_flags: Set file descriptor flags
static int32_t wasi_fd_fdstat_set_flags_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t flags
) {
    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;

#ifndef _WIN32
    int native_flags = 0;
    // WASI fdflags:
    // 0x01 = APPEND
    // 0x02 = DSYNC
    // 0x04 = NONBLOCK
    // 0x08 = RSYNC
    // 0x10 = SYNC
    if (flags & 0x01) native_flags |= O_APPEND;
#ifdef O_DSYNC
    if (flags & 0x02) native_flags |= O_DSYNC;
#endif
    if (flags & 0x04) native_flags |= O_NONBLOCK;
#ifdef O_SYNC
    if (flags & 0x10) native_flags |= O_SYNC;
#endif

    if (fcntl(native_fd, F_SETFL, native_flags) < 0) return WASI_EIO;
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// ============ FFI Export Functions ============

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_write_ptr(void) { return (int64_t)wasi_fd_write_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_read_ptr(void) { return (int64_t)wasi_fd_read_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_close_ptr(void) { return (int64_t)wasi_fd_close_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_seek_ptr(void) { return (int64_t)wasi_fd_seek_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_tell_ptr(void) { return (int64_t)wasi_fd_tell_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_sync_ptr(void) { return (int64_t)wasi_fd_sync_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_datasync_ptr(void) { return (int64_t)wasi_fd_datasync_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_fdstat_get_ptr(void) { return (int64_t)wasi_fd_fdstat_get_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_prestat_get_ptr(void) { return (int64_t)wasi_fd_prestat_get_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_prestat_dir_name_ptr(void) { return (int64_t)wasi_fd_prestat_dir_name_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_filestat_get_ptr(void) { return (int64_t)wasi_fd_filestat_get_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_filestat_set_size_ptr(void) { return (int64_t)wasi_fd_filestat_set_size_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_open_ptr(void) { return (int64_t)wasi_path_open_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_unlink_file_ptr(void) { return (int64_t)wasi_path_unlink_file_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_remove_directory_ptr(void) { return (int64_t)wasi_path_remove_directory_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_create_directory_ptr(void) { return (int64_t)wasi_path_create_directory_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_rename_ptr(void) { return (int64_t)wasi_path_rename_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_args_sizes_get_ptr(void) { return (int64_t)wasi_args_sizes_get_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_args_get_ptr(void) { return (int64_t)wasi_args_get_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_environ_sizes_get_ptr(void) { return (int64_t)wasi_environ_sizes_get_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_environ_get_ptr(void) { return (int64_t)wasi_environ_get_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_clock_time_get_ptr(void) { return (int64_t)wasi_clock_time_get_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_clock_res_get_ptr(void) { return (int64_t)wasi_clock_res_get_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_random_get_ptr(void) { return (int64_t)wasi_random_get_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_proc_exit_ptr(void) { return (int64_t)wasi_proc_exit_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_proc_raise_ptr(void) { return (int64_t)wasi_proc_raise_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_sched_yield_ptr(void) { return (int64_t)wasi_sched_yield_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_poll_oneoff_ptr(void) { return (int64_t)wasi_poll_oneoff_impl; }

// Implemented functions
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_advise_ptr(void) { return (int64_t)wasi_fd_advise_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_pread_ptr(void) { return (int64_t)wasi_fd_pread_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_pwrite_ptr(void) { return (int64_t)wasi_fd_pwrite_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_readdir_ptr(void) { return (int64_t)wasi_fd_readdir_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_fdstat_set_rights_ptr(void) { return (int64_t)wasi_fd_fdstat_set_rights_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_filestat_set_times_ptr(void) { return (int64_t)wasi_fd_filestat_set_times_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_filestat_get_ptr(void) { return (int64_t)wasi_path_filestat_get_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_filestat_set_times_ptr(void) { return (int64_t)wasi_path_filestat_set_times_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_link_ptr(void) { return (int64_t)wasi_path_link_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_readlink_ptr(void) { return (int64_t)wasi_path_readlink_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_symlink_ptr(void) { return (int64_t)wasi_path_symlink_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_allocate_ptr(void) { return (int64_t)wasi_fd_allocate_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_renumber_ptr(void) { return (int64_t)wasi_fd_renumber_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_fdstat_set_flags_ptr(void) { return (int64_t)wasi_fd_fdstat_set_flags_impl; }

// ============ Socket Operations ============

// Helper: Check if fd is a stdio fd (not a real socket)
// Returns true if fd is stdin/stdout/stderr
static inline int is_stdio_fd(int32_t fd) {
    return fd >= 0 && fd <= 2;
}

// sock_accept: Accept a connection on a socket
// fd: The listening socket
// flags: Desired flags for the accepted socket (currently unused)
// result_fd_ptr: Where to store the new socket fd
static int32_t wasi_sock_accept_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t flags, int32_t result_fd_ptr
) {
    (void)flags; // WASI doesn't use flags for accept yet
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t result_fd_ptr_u = (uint32_t)result_fd_ptr;
    if (!check_mem_range(ctx, result_fd_ptr_u, 4)) return WASI_EFAULT;

    // stdio fds are not sockets - return EBADF to match interpreter
    if (is_stdio_fd(fd)) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;

    uint8_t *mem = ctx->memory0->base;

#ifndef _WIN32
    int new_fd = accept(native_fd, NULL, NULL);
    if (new_fd < 0) return errno_to_wasi(errno);

    // Allocate a WASI fd for the new socket
    int wasi_fd = alloc_wasi_fd(ctx, new_fd);
    if (wasi_fd < 0) {
        close(new_fd);
        return WASI_ENOMEM;
    }

    *(uint32_t *)(mem + result_fd_ptr_u) = (uint32_t)wasi_fd;
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// sock_recv: Receive data from a socket
// fd: Socket to receive from
// ri_data: Pointer to iovec array for received data
// ri_data_len: Number of iovecs
// ri_flags: Message flags (PEEK=1, WAITALL=2)
// ro_datalen_ptr: Where to store bytes received
// ro_flags_ptr: Where to store output flags
static int32_t wasi_sock_recv_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t ri_data, int32_t ri_data_len, int32_t ri_flags,
    int32_t ro_datalen_ptr, int32_t ro_flags_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t ri_data_u = (uint32_t)ri_data;
    uint32_t ri_data_len_u = (uint32_t)ri_data_len;
    uint32_t ro_datalen_ptr_u = (uint32_t)ro_datalen_ptr;
    uint32_t ro_flags_ptr_u = (uint32_t)ro_flags_ptr;
    if (!check_mem_range(ctx, ri_data_u, (size_t)ri_data_len_u * 8)) return WASI_EFAULT;
    if (!check_mem_range(ctx, ro_datalen_ptr_u, 4)) return WASI_EFAULT;
    if (!check_mem_range(ctx, ro_flags_ptr_u, 4)) return WASI_EFAULT;

    // stdio fds are not sockets - return EBADF to match interpreter
    if (is_stdio_fd(fd)) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;

    uint8_t *mem = ctx->memory0->base;

#ifndef _WIN32
    // Convert WASI flags to native flags
    int flags = 0;
    if (ri_flags & 1) flags |= MSG_PEEK;
    if (ri_flags & 2) flags |= MSG_WAITALL;

    // Read into first iovec buffer (simplified implementation)
    size_t total = 0;
    for (uint32_t i = 0; i < ri_data_len_u; i++) {
        uint32_t buf_ptr = *(uint32_t *)(mem + ri_data_u + i * 8);
        uint32_t buf_len = *(uint32_t *)(mem + ri_data_u + i * 8 + 4);
        if (buf_len > 0 && !check_mem_range(ctx, buf_ptr, (size_t)buf_len)) {
            return WASI_EFAULT;
        }

        ssize_t n = recv(native_fd, mem + buf_ptr, buf_len, flags);
        if (n < 0) {
            if (total > 0) break; // Return what we have
            return errno_to_wasi(errno);
        }
        total += n;
        if (n < buf_len) break; // Short read
    }

    *(uint32_t *)(mem + ro_datalen_ptr_u) = (uint32_t)total;
    *(uint32_t *)(mem + ro_flags_ptr_u) = 0; // No output flags
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// sock_send: Send data on a socket
// fd: Socket to send on
// si_data: Pointer to iovec array of data to send
// si_data_len: Number of iovecs
// si_flags: Message flags (currently unused in WASI)
// so_datalen_ptr: Where to store bytes sent
static int32_t wasi_sock_send_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t si_data, int32_t si_data_len, int32_t si_flags,
    int32_t so_datalen_ptr
) {
    (void)si_flags; // WASI doesn't define send flags yet
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t si_data_u = (uint32_t)si_data;
    uint32_t si_data_len_u = (uint32_t)si_data_len;
    uint32_t so_datalen_ptr_u = (uint32_t)so_datalen_ptr;
    if (!check_mem_range(ctx, si_data_u, (size_t)si_data_len_u * 8)) return WASI_EFAULT;
    if (!check_mem_range(ctx, so_datalen_ptr_u, 4)) return WASI_EFAULT;

    // stdio fds are not sockets - return EBADF to match interpreter
    if (is_stdio_fd(fd)) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;

    uint8_t *mem = ctx->memory0->base;

#ifndef _WIN32
    size_t total = 0;
    for (uint32_t i = 0; i < si_data_len_u; i++) {
        uint32_t buf_ptr = *(uint32_t *)(mem + si_data_u + i * 8);
        uint32_t buf_len = *(uint32_t *)(mem + si_data_u + i * 8 + 4);
        if (buf_len > 0 && !check_mem_range(ctx, buf_ptr, (size_t)buf_len)) {
            return WASI_EFAULT;
        }

        ssize_t n = send(native_fd, mem + buf_ptr, buf_len, 0);
        if (n < 0) {
            if (total > 0) break; // Return what we sent
            return errno_to_wasi(errno);
        }
        total += n;
        if (n < buf_len) break; // Short write
    }

    *(uint32_t *)(mem + so_datalen_ptr_u) = (uint32_t)total;
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// sock_shutdown: Shut down a socket
// fd: Socket to shut down
// how: 0=RD, 1=WR, 2=RDWR
static int32_t wasi_sock_shutdown_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t how
) {

    // stdio fds are not sockets - return EBADF to match interpreter
    if (is_stdio_fd(fd)) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;

#ifndef _WIN32
    int native_how;
    switch (how) {
        case 0: native_how = SHUT_RD; break;
        case 1: native_how = SHUT_WR; break;
        case 2: native_how = SHUT_RDWR; break;
        default: return WASI_EINVAL;
    }

    if (shutdown(native_fd, native_how) < 0) {
        return errno_to_wasi(errno);
    }
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_sock_accept_ptr(void) { return (int64_t)wasi_sock_accept_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_sock_recv_ptr(void) { return (int64_t)wasi_sock_recv_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_sock_send_ptr(void) { return (int64_t)wasi_sock_send_impl; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_sock_shutdown_ptr(void) { return (int64_t)wasi_sock_shutdown_impl; }

// ============ Context Initialization ============

MOONBIT_FFI_EXPORT void wasmoon_jit_init_wasi_fds(int64_t ctx_ptr, int preopen_count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;

    ctx->preopen_base_fd = 3;
    ctx->preopen_count = preopen_count;
    ctx->fd_table_size = 64;
    ctx->fd_table = malloc(ctx->fd_table_size * sizeof(int));
    if (ctx->fd_table) {
        for (int i = 0; i < ctx->fd_table_size; i++) {
            ctx->fd_table[i] = -1;
        }
        // stdio
        ctx->fd_table[0] = 0;
        ctx->fd_table[1] = 1;
        ctx->fd_table[2] = 2;
    }
    if (ctx->fd_table && ensure_fd_metadata_arrays(ctx)) {
        // keep arrays initialized
    }
    ctx->fd_next = 3 + preopen_count;

    if (preopen_count > 0) {
        ctx->preopen_paths = malloc(preopen_count * sizeof(char*));
        ctx->preopen_guest_paths = malloc(preopen_count * sizeof(char*));
    }
}

// Quiet version: redirects stdout/stderr to /dev/null for testing
MOONBIT_FFI_EXPORT void wasmoon_jit_init_wasi_fds_quiet(int64_t ctx_ptr, int preopen_count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;

    ctx->preopen_base_fd = 3;
    ctx->preopen_count = preopen_count;
    ctx->fd_table_size = 64;
    ctx->fd_table = malloc(ctx->fd_table_size * sizeof(int));
    if (ctx->fd_table) {
        for (int i = 0; i < ctx->fd_table_size; i++) {
            ctx->fd_table[i] = -1;
        }
        // stdin from real stdin, stdout/stderr to /dev/null
        ctx->fd_table[0] = 0;
#ifndef _WIN32
        int devnull = open("/dev/null", O_WRONLY);
        ctx->fd_table[1] = devnull >= 0 ? devnull : 1;
        ctx->fd_table[2] = devnull >= 0 ? devnull : 2;
#else
        ctx->fd_table[1] = 1;
        ctx->fd_table[2] = 2;
#endif
    }
    if (ctx->fd_table && ensure_fd_metadata_arrays(ctx)) {
        // keep arrays initialized
    }
    ctx->fd_next = 3 + preopen_count;

    if (preopen_count > 0) {
        ctx->preopen_paths = malloc(preopen_count * sizeof(char*));
        ctx->preopen_guest_paths = malloc(preopen_count * sizeof(char*));
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_stdout_capture(int64_t ctx_ptr, int enabled) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;
    if (enabled) {
        ctx->wasi_stdout_capture = 1;
        ctx->wasi_stdout_len = 0;
    } else {
        ctx->wasi_stdout_capture = 0;
        if (ctx->wasi_stdout_buf) {
            free(ctx->wasi_stdout_buf);
        }
        ctx->wasi_stdout_buf = NULL;
        ctx->wasi_stdout_len = 0;
        ctx->wasi_stdout_cap = 0;
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_stderr_capture(int64_t ctx_ptr, int enabled) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;
    if (enabled) {
        ctx->wasi_stderr_capture = 1;
        ctx->wasi_stderr_len = 0;
    } else {
        ctx->wasi_stderr_capture = 0;
        if (ctx->wasi_stderr_buf) {
            free(ctx->wasi_stderr_buf);
        }
        ctx->wasi_stderr_buf = NULL;
        ctx->wasi_stderr_len = 0;
        ctx->wasi_stderr_cap = 0;
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_stdin_buffer(
    int64_t ctx_ptr,
    moonbit_bytes_t data,
    int len
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;
    clear_wasi_stdin_callback(ctx);
    clear_wasi_stdin_buffer(ctx);
    ctx->wasi_stdin_use_buffer = 1;
    if (len > 0) {
        ctx->wasi_stdin_buf = malloc((size_t)len);
        if (ctx->wasi_stdin_buf) {
            memcpy(ctx->wasi_stdin_buf, data, (size_t)len);
            ctx->wasi_stdin_len = (size_t)len;
        }
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_stdin_callback(
    int64_t ctx_ptr,
    wasi_stdin_callback_fn callback,
    void *closure
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;
    clear_wasi_stdin_buffer(ctx);
    clear_wasi_stdin_callback(ctx);
    ctx->wasi_stdin_callback = (void *)callback;
    ctx->wasi_stdin_callback_data = closure;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_wasi_stdin_buffer(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;
    clear_wasi_stdin_buffer(ctx);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_wasi_stdin_callback(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;
    clear_wasi_stdin_callback(ctx);
}

MOONBIT_FFI_EXPORT moonbit_bytes_t wasmoon_jit_take_wasi_stdout(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || !ctx->wasi_stdout_capture || ctx->wasi_stdout_len == 0) {
        return moonbit_make_bytes(0, 0);
    }
    moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)ctx->wasi_stdout_len, 0);
    memcpy(bytes, ctx->wasi_stdout_buf, ctx->wasi_stdout_len);
    ctx->wasi_stdout_len = 0;
    return bytes;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t wasmoon_jit_take_wasi_stderr(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || !ctx->wasi_stderr_capture || ctx->wasi_stderr_len == 0) {
        return moonbit_make_bytes(0, 0);
    }
    moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)ctx->wasi_stderr_len, 0);
    memcpy(bytes, ctx->wasi_stderr_buf, ctx->wasi_stderr_len);
    ctx->wasi_stderr_len = 0;
    return bytes;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_add_preopen(int64_t ctx_ptr, int idx, const char *host_path, const char *guest_path) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || !ctx->preopen_paths || idx < 0 || idx >= ctx->preopen_count) return;

    ctx->preopen_paths[idx] = strdup(host_path);
    ctx->preopen_guest_paths[idx] = strdup(guest_path);
#ifndef _WIN32
    if (ctx->fd_table) {
        int wasi_fd = ctx->preopen_base_fd + idx;
        if (wasi_fd >= 0 && wasi_fd < ctx->fd_table_size) {
            int native_fd = open(host_path, O_RDONLY | O_DIRECTORY);
            if (native_fd >= 0) {
                ctx->fd_table[wasi_fd] = native_fd;
                set_fd_metadata(ctx, wasi_fd, strdup(host_path), 1);
            }
        }
    }
#endif
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_args(int64_t ctx_ptr, int argc) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;

    // Free any existing args
    if (ctx->args) {
        for (int i = 0; i < ctx->argc; i++) {
            free(ctx->args[i]);
        }
        free(ctx->args);
    }

    ctx->argc = argc;
    if (argc > 0) {
        ctx->args = malloc(argc * sizeof(char*));
        for (int i = 0; i < argc; i++) {
            ctx->args[i] = NULL;
        }
    } else {
        ctx->args = NULL;
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_arg(int64_t ctx_ptr, int idx, const char *arg) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || !ctx->args || idx < 0 || idx >= ctx->argc) return;

    if (ctx->args[idx]) {
        free(ctx->args[idx]);
    }
    ctx->args[idx] = strdup(arg);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_envs(int64_t ctx_ptr, int envc) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;

    // Free any existing envp
    if (ctx->envp) {
        for (int i = 0; i < ctx->envc; i++) {
            free(ctx->envp[i]);
        }
        free(ctx->envp);
    }

    ctx->envc = envc;
    if (envc > 0) {
        ctx->envp = malloc(envc * sizeof(char*));
        for (int i = 0; i < envc; i++) {
            ctx->envp[i] = NULL;
        }
    } else {
        ctx->envp = NULL;
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_env(int64_t ctx_ptr, int idx, const char *env) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || !ctx->envp || idx < 0 || idx >= ctx->envc) return;

    if (ctx->envp[idx]) {
        free(ctx->envp[idx]);
    }
    ctx->envp[idx] = strdup(env);
}

MOONBIT_FFI_EXPORT int wasmoon_jit_get_wasi_exit_code(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || !ctx->wasi_exited) return -1;
    return ctx->wasi_exit_code;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_wasi_exit(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;
    ctx->wasi_exited = 0;
    ctx->wasi_exit_code = 0;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_free_wasi_fds(int64_t ctx_ptr) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;

    // Free args
    if (ctx->args) {
        for (int i = 0; i < ctx->argc; i++) {
            free(ctx->args[i]);
        }
        free(ctx->args);
        ctx->args = NULL;
    }
    ctx->argc = 0;

    // Free envp
    if (ctx->envp) {
        for (int i = 0; i < ctx->envc; i++) {
            free(ctx->envp[i]);
        }
        free(ctx->envp);
        ctx->envp = NULL;
    }
    ctx->envc = 0;

    // Close all open fds (except stdio)
    if (ctx->fd_table) {
#ifndef _WIN32
        int fd1 = ctx->fd_table[1];
        int fd2 = ctx->fd_table[2];
        if (fd1 > 2) close(fd1);
        if (fd2 > 2 && fd2 != fd1) close(fd2);
#endif
        for (int i = 3; i < ctx->fd_table_size; i++) {
            if (ctx->fd_table[i] >= 0) {
#ifndef _WIN32
                close(ctx->fd_table[i]);
#endif
            }
        }
        if (ctx->fd_host_paths) {
            for (int i = 0; i < ctx->fd_table_size; i++) {
                if (ctx->fd_host_paths[i]) {
                    free(ctx->fd_host_paths[i]);
                }
            }
            free(ctx->fd_host_paths);
            ctx->fd_host_paths = NULL;
        }
        if (ctx->fd_is_dir) {
            free(ctx->fd_is_dir);
            ctx->fd_is_dir = NULL;
        }
        free(ctx->fd_table);
        ctx->fd_table = NULL;
    }

    if (ctx->preopen_paths) {
        for (int i = 0; i < ctx->preopen_count; i++) {
            free(ctx->preopen_paths[i]);
            free(ctx->preopen_guest_paths[i]);
        }
        free(ctx->preopen_paths);
        free(ctx->preopen_guest_paths);
        ctx->preopen_paths = NULL;
        ctx->preopen_guest_paths = NULL;
    }

    // Free stdio buffers
    clear_wasi_stdin_callback(ctx);
    clear_wasi_stdin_buffer(ctx);

    ctx->wasi_stdout_capture = 0;
    if (ctx->wasi_stdout_buf) {
        free(ctx->wasi_stdout_buf);
        ctx->wasi_stdout_buf = NULL;
    }
    ctx->wasi_stdout_len = 0;
    ctx->wasi_stdout_cap = 0;

    ctx->wasi_stderr_capture = 0;
    if (ctx->wasi_stderr_buf) {
        free(ctx->wasi_stderr_buf);
        ctx->wasi_stderr_buf = NULL;
    }
    ctx->wasi_stderr_len = 0;
    ctx->wasi_stderr_cap = 0;
}
