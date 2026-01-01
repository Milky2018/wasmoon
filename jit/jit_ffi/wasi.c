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
#endif

#include "moonbit.h"
#include "jit_ffi.h"

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
#define WASI_ENOSYS       52
#define WASI_ENOTDIR      54
#define WASI_ENOTEMPTY    55
#define WASI_ESPIPE       70

// ============ WASI File Types ============
#define WASI_FILETYPE_UNKNOWN          0
#define WASI_FILETYPE_BLOCK_DEVICE     1
#define WASI_FILETYPE_CHARACTER_DEVICE 2
#define WASI_FILETYPE_DIRECTORY        3
#define WASI_FILETYPE_REGULAR_FILE     4
#define WASI_FILETYPE_SOCKET_DGRAM     5
#define WASI_FILETYPE_SOCKET_STREAM    6
#define WASI_FILETYPE_SYMBOLIC_LINK    7

// ============ Helper Functions ============

// Get native fd from WASI fd
static int get_native_fd(jit_context_t *ctx, int wasi_fd) {
    if (wasi_fd < 0) return -1;
    // stdio fds map directly
    if (wasi_fd < 3) return wasi_fd;
    // Check fd table
    if (!ctx->fd_table || wasi_fd >= ctx->fd_table_size) return -1;
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

// Resolve path relative to a directory fd
static char* resolve_path(jit_context_t *ctx, int dir_fd, const char *path) {
    const char *base = get_preopen_path(ctx, dir_fd);
    if (!base) return NULL;

    size_t base_len = strlen(base);
    size_t path_len = strlen(path);
    char *result = malloc(base_len + path_len + 2);
    if (!result) return NULL;

    strcpy(result, base);
    if (base_len > 0 && base[base_len-1] != '/') {
        strcat(result, "/");
    }
    strcat(result, path);
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
        ctx->fd_next = 3 + ctx->preopen_count;
    }

    // Find next available slot
    for (int i = ctx->fd_next; i < ctx->fd_table_size; i++) {
        if (ctx->fd_table[i] < 0) {
            ctx->fd_table[i] = native_fd;
            ctx->fd_next = i + 1;
            return i;
        }
    }

    // Expand table
    int new_size = ctx->fd_table_size * 2;
    int *new_table = realloc(ctx->fd_table, new_size * sizeof(int));
    if (!new_table) return -1;
    for (int i = ctx->fd_table_size; i < new_size; i++) {
        new_table[i] = -1;
    }
    int fd = ctx->fd_table_size;
    new_table[fd] = native_fd;
    ctx->fd_table = new_table;
    ctx->fd_table_size = new_size;
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

// ============ WASI Trampolines ============
// JIT ABI v3: X0 = callee_vmctx, X1 = caller_vmctx, X2.. = WASM arguments.

// fd_write: (fd, iovs, iovs_len, nwritten) -> errno
static int64_t wasi_fd_write_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t fd, int64_t iovs, int64_t iovs_len, int64_t nwritten_ptr
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    uint8_t *mem = ctx->memory_base;
    int native_fd = get_native_fd(ctx, (int)fd);
    if (native_fd < 0) return WASI_EBADF;

    int32_t total = 0;
    for (int64_t i = 0; i < iovs_len; i++) {
        int32_t buf_ptr = *(int32_t *)(mem + iovs + i * 8);
        int32_t buf_len = *(int32_t *)(mem + iovs + i * 8 + 4);
        if (buf_len > 0) {
#ifdef _WIN32
            int n = _write(native_fd, mem + buf_ptr, buf_len);
#else
            ssize_t n = write(native_fd, mem + buf_ptr, buf_len);
#endif
            if (n < 0) return errno_to_wasi(errno);
            total += (int32_t)n;
        }
    }

    *(int32_t *)(mem + nwritten_ptr) = total;
    return WASI_ESUCCESS;
}

// fd_read: (fd, iovs, iovs_len, nread) -> errno
static int64_t wasi_fd_read_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t fd, int64_t iovs, int64_t iovs_len, int64_t nread_ptr
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    uint8_t *mem = ctx->memory_base;
    int native_fd = get_native_fd(ctx, (int)fd);
    if (native_fd < 0) return WASI_EBADF;

    int32_t total = 0;
    for (int64_t i = 0; i < iovs_len; i++) {
        int32_t buf_ptr = *(int32_t *)(mem + iovs + i * 8);
        int32_t buf_len = *(int32_t *)(mem + iovs + i * 8 + 4);
        if (buf_len > 0) {
#ifdef _WIN32
            int n = _read(native_fd, mem + buf_ptr, buf_len);
#else
            ssize_t n = read(native_fd, mem + buf_ptr, buf_len);
#endif
            if (n < 0) return errno_to_wasi(errno);
            total += (int32_t)n;
            if (n < buf_len) break; // EOF or partial read
        }
    }

    *(int32_t *)(mem + nread_ptr) = total;
    return WASI_ESUCCESS;
}

// fd_close: (fd) -> errno
static int64_t wasi_fd_close_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx, int64_t fd
) {
    (void)caller_ctx;
    if (!ctx) return WASI_EBADF;

    int wasi_fd = (int)fd;
    if (wasi_fd < 3) return WASI_ESUCCESS; // Can't close stdio
    if (is_preopen_fd(ctx, wasi_fd)) return WASI_EBADF; // Can't close preopens

    int native_fd = get_native_fd(ctx, wasi_fd);
    if (native_fd < 0) return WASI_EBADF;

#ifdef _WIN32
    _close(native_fd);
#else
    close(native_fd);
#endif
    ctx->fd_table[wasi_fd] = -1;
    return WASI_ESUCCESS;
}

// fd_seek: (fd, offset, whence, newoffset) -> errno
static int64_t wasi_fd_seek_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t fd, int64_t offset, int64_t whence, int64_t newoffset_ptr
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, (int)fd);
    if (native_fd < 0) return WASI_EBADF;
    if (native_fd < 3) return WASI_ESPIPE; // stdio not seekable

#ifdef _WIN32
    int64_t pos = _lseeki64(native_fd, offset, (int)whence);
#else
    off_t pos = lseek(native_fd, offset, (int)whence);
#endif
    if (pos < 0) return errno_to_wasi(errno);

    *(int64_t *)(ctx->memory_base + newoffset_ptr) = pos;
    return WASI_ESUCCESS;
}

// fd_tell: (fd, offset) -> errno
static int64_t wasi_fd_tell_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t fd, int64_t offset_ptr
) {
    return wasi_fd_seek_impl(ctx, caller_ctx, fd, 0, 1 /* SEEK_CUR */, offset_ptr);
}

// fd_sync: (fd) -> errno
static int64_t wasi_fd_sync_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx, int64_t fd
) {
    (void)caller_ctx;
    if (!ctx) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, (int)fd);
    if (native_fd < 0) return WASI_EBADF;

#ifdef _WIN32
    return WASI_ESUCCESS; // No sync on Windows
#else
    if (fsync(native_fd) < 0) return errno_to_wasi(errno);
    return WASI_ESUCCESS;
#endif
}

// fd_datasync: (fd) -> errno
static int64_t wasi_fd_datasync_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx, int64_t fd
) {
    (void)caller_ctx;
    if (!ctx) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, (int)fd);
    if (native_fd < 0) return WASI_EBADF;

#ifdef _WIN32
    return WASI_ESUCCESS;
#elif defined(__APPLE__)
    if (fsync(native_fd) < 0) return errno_to_wasi(errno);
    return WASI_ESUCCESS;
#else
    if (fdatasync(native_fd) < 0) return errno_to_wasi(errno);
    return WASI_ESUCCESS;
#endif
}

// fd_fdstat_get: (fd, fdstat) -> errno
static int64_t wasi_fd_fdstat_get_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t fd, int64_t fdstat_ptr
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    uint8_t *mem = ctx->memory_base;
    int wasi_fd = (int)fd;

    // Determine file type
    uint8_t filetype;
    if (wasi_fd < 3) {
        filetype = WASI_FILETYPE_CHARACTER_DEVICE;
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
    mem[fdstat_ptr] = filetype;
    mem[fdstat_ptr + 1] = 0;
    *(uint16_t *)(mem + fdstat_ptr + 2) = 0;
    *(uint32_t *)(mem + fdstat_ptr + 4) = 0;
    *(uint64_t *)(mem + fdstat_ptr + 8) = 0x1FFFFFFFULL; // all rights
    *(uint64_t *)(mem + fdstat_ptr + 16) = 0x1FFFFFFFULL;
    return WASI_ESUCCESS;
}

// fd_prestat_get: (fd, prestat) -> errno
static int64_t wasi_fd_prestat_get_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t fd, int64_t prestat_ptr
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    int wasi_fd = (int)fd;
    if (!is_preopen_fd(ctx, wasi_fd)) return WASI_EBADF;

    int idx = wasi_fd - ctx->preopen_base_fd;
    const char *guest_path = ctx->preopen_guest_paths[idx];
    size_t len = strlen(guest_path);

    uint8_t *mem = ctx->memory_base;
    mem[prestat_ptr] = 0; // tag = dir
    mem[prestat_ptr + 1] = 0;
    mem[prestat_ptr + 2] = 0;
    mem[prestat_ptr + 3] = 0;
    *(uint32_t *)(mem + prestat_ptr + 4) = (uint32_t)len;
    return WASI_ESUCCESS;
}

// fd_prestat_dir_name: (fd, path, path_len) -> errno
static int64_t wasi_fd_prestat_dir_name_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t fd, int64_t path_ptr, int64_t path_len
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    int wasi_fd = (int)fd;
    if (!is_preopen_fd(ctx, wasi_fd)) return WASI_EBADF;

    int idx = wasi_fd - ctx->preopen_base_fd;
    const char *guest_path = ctx->preopen_guest_paths[idx];
    size_t len = strlen(guest_path);
    size_t to_copy = (size_t)path_len < len ? (size_t)path_len : len;

    memcpy(ctx->memory_base + path_ptr, guest_path, to_copy);
    return WASI_ESUCCESS;
}

// path_open: (fd, dirflags, path, path_len, oflags, rights_base, rights_inh, fdflags, opened_fd) -> errno
static int64_t wasi_path_open_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t dir_fd, int64_t dirflags,
    int64_t path_ptr, int64_t path_len,
    int64_t oflags, int64_t rights_base, int64_t rights_inh,
    int64_t fdflags, int64_t opened_fd_ptr
) {
    (void)caller_ctx;
    (void)dirflags;
    (void)rights_base;
    (void)rights_inh;

    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    // Read path from memory
    char *path = malloc((size_t)path_len + 1);
    if (!path) return WASI_EIO;
    memcpy(path, ctx->memory_base + path_ptr, (size_t)path_len);
    path[path_len] = '\0';

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
    free(full_path);
    if (native_fd < 0) return errno_to_wasi(errno);

    int wasi_fd = alloc_wasi_fd(ctx, native_fd);
    if (wasi_fd < 0) {
        close(native_fd);
        return WASI_EIO;
    }

    *(int32_t *)(ctx->memory_base + opened_fd_ptr) = wasi_fd;
    return WASI_ESUCCESS;
#else
    free(full_path);
    return WASI_ENOSYS;
#endif
}

// path_unlink_file: (fd, path, path_len) -> errno
static int64_t wasi_path_unlink_file_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t dir_fd, int64_t path_ptr, int64_t path_len
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    char *path = malloc((size_t)path_len + 1);
    if (!path) return WASI_EIO;
    memcpy(path, ctx->memory_base + path_ptr, (size_t)path_len);
    path[path_len] = '\0';

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
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t dir_fd, int64_t path_ptr, int64_t path_len
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    char *path = malloc((size_t)path_len + 1);
    if (!path) return WASI_EIO;
    memcpy(path, ctx->memory_base + path_ptr, (size_t)path_len);
    path[path_len] = '\0';

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
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t dir_fd, int64_t path_ptr, int64_t path_len
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    char *path = malloc((size_t)path_len + 1);
    if (!path) return WASI_EIO;
    memcpy(path, ctx->memory_base + path_ptr, (size_t)path_len);
    path[path_len] = '\0';

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
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t old_fd, int64_t old_path_ptr, int64_t old_path_len,
    int64_t new_fd, int64_t new_path_ptr, int64_t new_path_len
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    char *old_path = malloc((size_t)old_path_len + 1);
    char *new_path = malloc((size_t)new_path_len + 1);
    if (!old_path || !new_path) {
        free(old_path);
        free(new_path);
        return WASI_EIO;
    }

    memcpy(old_path, ctx->memory_base + old_path_ptr, (size_t)old_path_len);
    old_path[old_path_len] = '\0';
    memcpy(new_path, ctx->memory_base + new_path_ptr, (size_t)new_path_len);
    new_path[new_path_len] = '\0';

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
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t fd, int64_t buf_ptr
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    uint8_t *mem = ctx->memory_base;
    int wasi_fd = (int)fd;

    // Handle stdio
    if (wasi_fd < 3) {
        memset(mem + buf_ptr, 0, 64);
        mem[buf_ptr + 16] = WASI_FILETYPE_CHARACTER_DEVICE;
        *(uint64_t *)(mem + buf_ptr + 24) = 1; // nlink
        return WASI_ESUCCESS;
    }

    // Handle preopens
    if (is_preopen_fd(ctx, wasi_fd)) {
        memset(mem + buf_ptr, 0, 64);
        mem[buf_ptr + 16] = WASI_FILETYPE_DIRECTORY;
        *(uint64_t *)(mem + buf_ptr + 24) = 1;
        return WASI_ESUCCESS;
    }

#ifndef _WIN32
    int native_fd = get_native_fd(ctx, wasi_fd);
    if (native_fd < 0) return WASI_EBADF;

    struct stat st;
    if (fstat(native_fd, &st) < 0) return errno_to_wasi(errno);

    *(uint64_t *)(mem + buf_ptr) = st.st_dev;
    *(uint64_t *)(mem + buf_ptr + 8) = st.st_ino;
    mem[buf_ptr + 16] = mode_to_filetype(st.st_mode);
    memset(mem + buf_ptr + 17, 0, 7);
    *(uint64_t *)(mem + buf_ptr + 24) = st.st_nlink;
    *(uint64_t *)(mem + buf_ptr + 32) = st.st_size;
#ifdef __APPLE__
    *(uint64_t *)(mem + buf_ptr + 40) = st.st_atimespec.tv_sec * 1000000000ULL + st.st_atimespec.tv_nsec;
    *(uint64_t *)(mem + buf_ptr + 48) = st.st_mtimespec.tv_sec * 1000000000ULL + st.st_mtimespec.tv_nsec;
    *(uint64_t *)(mem + buf_ptr + 56) = st.st_ctimespec.tv_sec * 1000000000ULL + st.st_ctimespec.tv_nsec;
#else
    *(uint64_t *)(mem + buf_ptr + 40) = st.st_atim.tv_sec * 1000000000ULL + st.st_atim.tv_nsec;
    *(uint64_t *)(mem + buf_ptr + 48) = st.st_mtim.tv_sec * 1000000000ULL + st.st_mtim.tv_nsec;
    *(uint64_t *)(mem + buf_ptr + 56) = st.st_ctim.tv_sec * 1000000000ULL + st.st_ctim.tv_nsec;
#endif
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// fd_filestat_set_size: (fd, size) -> errno
static int64_t wasi_fd_filestat_set_size_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t fd, int64_t size
) {
    (void)caller_ctx;
    if (!ctx) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, (int)fd);
    if (native_fd < 0) return WASI_EBADF;

#ifndef _WIN32
    if (ftruncate(native_fd, size) < 0) return errno_to_wasi(errno);
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

// args_sizes_get: (argc, argv_buf_size) -> errno
static int64_t wasi_args_sizes_get_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t argc_ptr, int64_t argv_buf_size_ptr
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    uint8_t *mem = ctx->memory_base;
    int argc = ctx->argc;
    char **args = ctx->args;

    size_t buf_size = 0;
    for (int i = 0; i < argc; i++) {
        buf_size += strlen(args[i]) + 1;
    }

    *(int32_t *)(mem + argc_ptr) = argc;
    *(int32_t *)(mem + argv_buf_size_ptr) = (int32_t)buf_size;
    return WASI_ESUCCESS;
}

// args_get: (argv, argv_buf) -> errno
static int64_t wasi_args_get_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t argv_ptr, int64_t argv_buf_ptr
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    uint8_t *mem = ctx->memory_base;
    int argc = ctx->argc;
    char **args = ctx->args;

    int32_t buf_offset = (int32_t)argv_buf_ptr;
    for (int i = 0; i < argc; i++) {
        *(int32_t *)(mem + argv_ptr + i * 4) = buf_offset;
        size_t len = strlen(args[i]) + 1;
        memcpy(mem + buf_offset, args[i], len);
        buf_offset += (int32_t)len;
    }
    return WASI_ESUCCESS;
}

// environ_sizes_get: (environc, environ_buf_size) -> errno
static int64_t wasi_environ_sizes_get_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t environc_ptr, int64_t environ_buf_size_ptr
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    uint8_t *mem = ctx->memory_base;
    int envc = ctx->envc;
    char **envp = ctx->envp;

    size_t buf_size = 0;
    for (int i = 0; i < envc; i++) {
        buf_size += strlen(envp[i]) + 1;
    }

    *(int32_t *)(mem + environc_ptr) = envc;
    *(int32_t *)(mem + environ_buf_size_ptr) = (int32_t)buf_size;
    return WASI_ESUCCESS;
}

// environ_get: (environ, environ_buf) -> errno
static int64_t wasi_environ_get_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t environ_ptr, int64_t environ_buf_ptr
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    uint8_t *mem = ctx->memory_base;
    int envc = ctx->envc;
    char **envp = ctx->envp;

    int32_t buf_offset = (int32_t)environ_buf_ptr;
    for (int i = 0; i < envc; i++) {
        *(int32_t *)(mem + environ_ptr + i * 4) = buf_offset;
        size_t len = strlen(envp[i]) + 1;
        memcpy(mem + buf_offset, envp[i], len);
        buf_offset += (int32_t)len;
    }
    return WASI_ESUCCESS;
}

// clock_time_get: (clock_id, precision, time) -> errno
static int64_t wasi_clock_time_get_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t clock_id, int64_t precision, int64_t time_ptr
) {
    (void)caller_ctx;
    (void)precision;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    int64_t time_ns = 0;
    if (clock_id == 0 || clock_id == 1) {
#ifdef _WIN32
        FILETIME ft;
        GetSystemTimeAsFileTime(&ft);
        uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
        time_ns = (int64_t)((t - 116444736000000000ULL) * 100);
#else
        struct timespec ts;
        clock_gettime(clock_id == 0 ? CLOCK_REALTIME : CLOCK_MONOTONIC, &ts);
        time_ns = (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
    } else {
        return WASI_EINVAL;
    }

    *(int64_t *)(ctx->memory_base + time_ptr) = time_ns;
    return WASI_ESUCCESS;
}

// clock_res_get: (clock_id, resolution) -> errno
static int64_t wasi_clock_res_get_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t clock_id, int64_t resolution_ptr
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    if (clock_id != 0 && clock_id != 1) return WASI_EINVAL;

    *(int64_t *)(ctx->memory_base + resolution_ptr) = 1000000; // 1ms
    return WASI_ESUCCESS;
}

// random_get: (buf, buf_len) -> errno
static int64_t wasi_random_get_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t buf_ptr, int64_t buf_len
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    uint8_t *mem = ctx->memory_base;
    for (int64_t i = 0; i < buf_len; i++) {
        mem[buf_ptr + i] = (uint8_t)(rand() & 0xFF);
    }
    return WASI_ESUCCESS;
}

// proc_exit: (exit_code) -> noreturn
static int64_t wasi_proc_exit_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx, int64_t exit_code
) {
    (void)ctx;
    (void)caller_ctx;
    exit((int)exit_code);
    return 0;
}

// proc_raise: (signal) -> errno
static int64_t wasi_proc_raise_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx, int64_t sig
) {
    (void)ctx;
    (void)caller_ctx;
    if (raise((int)sig) < 0) return errno_to_wasi(errno);
    return WASI_ESUCCESS;
}

// sched_yield: () -> errno
static int64_t wasi_sched_yield_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx
) {
    (void)ctx;
    (void)caller_ctx;
#ifndef _WIN32
    sched_yield();
#endif
    return WASI_ESUCCESS;
}

// poll_oneoff: (in, out, nsubscriptions, nevents) -> errno
static int64_t wasi_poll_oneoff_impl(
    jit_context_t *ctx, jit_context_t *caller_ctx,
    int64_t in_ptr, int64_t out_ptr, int64_t nsubscriptions, int64_t nevents_ptr
) {
    (void)caller_ctx;
    if (!ctx || !ctx->memory_base) return WASI_EBADF;

    // Simplified: just handle clock subscriptions with sleep
    uint8_t *mem = ctx->memory_base;
    int64_t min_timeout = -1;

    for (int64_t i = 0; i < nsubscriptions; i++) {
        int64_t sub = in_ptr + i * 48;
        uint8_t tag = mem[sub + 8];
        if (tag == 0) { // Clock
            int64_t timeout = *(int64_t *)(mem + sub + 24);
            if (min_timeout < 0 || timeout < min_timeout) {
                min_timeout = timeout;
            }
        }
    }

    if (min_timeout > 0) {
#ifndef _WIN32
        struct timespec ts = {
            .tv_sec = min_timeout / 1000000000LL,
            .tv_nsec = min_timeout % 1000000000LL
        };
        nanosleep(&ts, NULL);
#endif
    }

    // Write events for clock subscriptions
    int32_t events = 0;
    for (int64_t i = 0; i < nsubscriptions; i++) {
        int64_t sub = in_ptr + i * 48;
        uint8_t tag = mem[sub + 8];
        if (tag == 0) {
            int64_t userdata = *(int64_t *)(mem + sub);
            int64_t evt = out_ptr + events * 32;
            *(int64_t *)(mem + evt) = userdata;
            *(uint16_t *)(mem + evt + 8) = 0; // error = success
            mem[evt + 10] = 0; // type = clock
            memset(mem + evt + 11, 0, 21);
            events++;
        }
    }

    *(int32_t *)(mem + nevents_ptr) = events;
    return WASI_ESUCCESS;
}

// Stub functions for less common operations
static int64_t wasi_stub_nosys(jit_context_t *ctx, jit_context_t *caller_ctx) {
    (void)ctx; (void)caller_ctx;
    return WASI_ENOSYS;
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

// Stub exports for less common functions
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_advise_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_allocate_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_pread_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_pwrite_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_readdir_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_renumber_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_fdstat_set_flags_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_fdstat_set_rights_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_fd_filestat_set_times_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_filestat_get_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_filestat_set_times_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_link_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_readlink_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_path_symlink_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_sock_accept_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_sock_recv_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_sock_send_ptr(void) { return (int64_t)wasi_stub_nosys; }
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_get_sock_shutdown_ptr(void) { return (int64_t)wasi_stub_nosys; }

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
    ctx->fd_next = 3 + preopen_count;

    if (preopen_count > 0) {
        ctx->preopen_paths = malloc(preopen_count * sizeof(char*));
        ctx->preopen_guest_paths = malloc(preopen_count * sizeof(char*));
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_add_preopen(int64_t ctx_ptr, int idx, const char *host_path, const char *guest_path) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || !ctx->preopen_paths || idx < 0 || idx >= ctx->preopen_count) return;

    ctx->preopen_paths[idx] = strdup(host_path);
    ctx->preopen_guest_paths[idx] = strdup(guest_path);
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
        for (int i = 3; i < ctx->fd_table_size; i++) {
            if (ctx->fd_table[i] >= 0 && !is_preopen_fd(ctx, i)) {
#ifndef _WIN32
                close(ctx->fd_table[i]);
#endif
            }
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
}
