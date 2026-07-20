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
#include <sys/ioctl.h>
#include <sched.h>
#ifdef __linux__
#include <sys/random.h>
#endif
#else
#include <windows.h>
#include <bcrypt.h>
#include <io.h>
#endif

#include "moonbit.h"
#include "jit_internal.h"

// ============ WASI Error Codes ============
#define WASI_ESUCCESS     0
#define WASI_E2BIG        1
#define WASI_EACCES       2
#define WASI_EBADF        8
#define WASI_EEXIST       20
#define WASI_EILSEQ       25
#define WASI_EINVAL       28
#define WASI_EIO          29
#define WASI_EISDIR       31
#define WASI_ENOENT       44
#define WASI_ENOMEM       48
#define WASI_ENOSYS       52
#define WASI_ENOTDIR      54
#define WASI_ENOTEMPTY    55
#define WASI_ENOTSOCK     57
#define WASI_ENOTSUP      58
#define WASI_EPERM        63
#define WASI_ESPIPE       70
#define WASI_ENAMETOOLONG 37
#define WASI_EFAULT       21
#define WASI_ENOTCAPABLE  76
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

// WASI rights: valid bits are 0-29
#define WASI_RIGHTS_ALL_VALID ((uint64_t)((1ULL << 30) - 1))
#define WASI_RIGHT_FD_DATASYNC          (1ULL << 0)
#define WASI_RIGHT_FD_READ              (1ULL << 1)
#define WASI_RIGHT_FD_SEEK              (1ULL << 2)
#define WASI_RIGHT_FD_FDSTAT_SET_FLAGS  (1ULL << 3)
#define WASI_RIGHT_FD_SYNC              (1ULL << 4)
#define WASI_RIGHT_FD_TELL              (1ULL << 5)
#define WASI_RIGHT_FD_WRITE             (1ULL << 6)
#define WASI_RIGHT_FD_ADVISE            (1ULL << 7)
#define WASI_RIGHT_FD_ALLOCATE          (1ULL << 8)
#define WASI_RIGHT_PATH_CREATE_DIRECTORY (1ULL << 9)
#define WASI_RIGHT_PATH_CREATE_FILE      (1ULL << 10)
#define WASI_RIGHT_PATH_LINK_SOURCE      (1ULL << 11)
#define WASI_RIGHT_PATH_LINK_TARGET      (1ULL << 12)
#define WASI_RIGHT_PATH_OPEN             (1ULL << 13)
#define WASI_RIGHT_FD_READDIR            (1ULL << 14)
#define WASI_RIGHT_PATH_READLINK         (1ULL << 15)
#define WASI_RIGHT_PATH_RENAME_SOURCE    (1ULL << 16)
#define WASI_RIGHT_PATH_RENAME_TARGET    (1ULL << 17)
#define WASI_RIGHT_PATH_FILESTAT_GET     (1ULL << 18)
#define WASI_RIGHT_PATH_FILESTAT_SET_SIZE  (1ULL << 19)
#define WASI_RIGHT_PATH_FILESTAT_SET_TIMES (1ULL << 20)
#define WASI_RIGHT_FD_FILESTAT_GET       (1ULL << 21)
#define WASI_RIGHT_FD_FILESTAT_SET_SIZE  (1ULL << 22)
#define WASI_RIGHT_FD_FILESTAT_SET_TIMES (1ULL << 23)
#define WASI_RIGHT_PATH_SYMLINK          (1ULL << 24)
#define WASI_RIGHT_PATH_REMOVE_DIRECTORY (1ULL << 25)
#define WASI_RIGHT_PATH_UNLINK_FILE      (1ULL << 26)
#define WASI_RIGHT_POLL_FD_READWRITE     (1ULL << 27)
#define WASI_RIGHT_SOCK_SHUTDOWN         (1ULL << 28)
#define WASI_RIGHT_SOCK_ACCEPT           (1ULL << 29)

// ============ Helper Functions ============

static int stdio_slot_for_fd(jit_context_t *ctx, int wasi_fd);

// Get native fd from WASI fd
static int get_native_fd(jit_context_t *ctx, int wasi_fd) {
    if (!ctx) return -1;
    if (wasi_fd < 0) return -1;
    // Check fd table for all fds (including stdio for quiet mode support)
    if (!ctx->fd_table || wasi_fd >= ctx->fd_table_size) {
        int stdio_slot = stdio_slot_for_fd(ctx, wasi_fd);
        if (stdio_slot == 0) return 0;
        if (stdio_slot == 1) return 1;
        if (stdio_slot == 2) return 2;
        return -3;
    }
    return ctx->fd_table[wasi_fd];
}

static int require_base_rights(
    jit_context_t *ctx,
    int wasi_fd,
    uint64_t required
) {
    if (!ctx || wasi_fd < 0 || !ctx->fd_table ||
        wasi_fd >= ctx->fd_table_size || ctx->fd_table[wasi_fd] < 0 ||
        !ctx->fd_rights_base) {
        return WASI_EBADF;
    }
    return (ctx->fd_rights_base[wasi_fd] & required) == required
        ? WASI_ESUCCESS
        : WASI_ENOTCAPABLE;
}

static int stdio_slot_for_fd(jit_context_t *ctx, int wasi_fd) {
    if (!ctx) return -1;
    if (wasi_fd == ctx->stdin_fd) return 0;
    if (wasi_fd == ctx->stdout_fd) return 1;
    if (wasi_fd == ctx->stderr_fd) return 2;
    return -1;
}

static int is_stdio_fd(jit_context_t *ctx, int wasi_fd) {
    return stdio_slot_for_fd(ctx, wasi_fd) >= 0;
}

static void clear_stdio_slot(jit_context_t *ctx, int slot) {
    if (!ctx) return;
    if (slot == 0) {
        ctx->stdin_fd = -1;
    } else if (slot == 1) {
        ctx->stdout_fd = -1;
    } else if (slot == 2) {
        ctx->stderr_fd = -1;
    }
}

static void move_stdio_slot_to_fd(jit_context_t *ctx, int slot, int wasi_fd) {
    if (!ctx) return;
    if (slot == 0) {
        ctx->stdin_fd = wasi_fd;
    } else if (slot == 1) {
        ctx->stdout_fd = wasi_fd;
    } else if (slot == 2) {
        ctx->stderr_fd = wasi_fd;
    }
}

static int preopen_index_for_fd(jit_context_t *ctx, int wasi_fd) {
    if (!ctx || !ctx->preopen_fds || !ctx->preopen_paths) return -1;
    for (int i = 0; i < ctx->preopen_count; i++) {
        if (ctx->preopen_fds[i] == wasi_fd) return i;
    }
    return -1;
}

// Check if fd is a preopen directory
static int is_preopen_fd(jit_context_t *ctx, int wasi_fd) {
    int idx = preopen_index_for_fd(ctx, wasi_fd);
    if (idx < 0) return 0;
    return get_native_fd(ctx, wasi_fd) >= 0;
}

// Get preopen host path
static const char* get_preopen_path(jit_context_t *ctx, int wasi_fd) {
    int idx = preopen_index_for_fd(ctx, wasi_fd);
    if (idx < 0) return NULL;
    if (get_native_fd(ctx, wasi_fd) < 0) return NULL;
    return ctx->preopen_paths[idx];
}

static const char* get_open_dir_path(jit_context_t *ctx, int wasi_fd) {
    if (!ctx->fd_host_paths || !ctx->fd_is_dir) return NULL;
    if (wasi_fd < 0 || wasi_fd >= ctx->fd_table_size) return NULL;
    if (!ctx->fd_is_dir[wasi_fd]) return NULL;
    return ctx->fd_host_paths[wasi_fd];
}

static int is_valid_wasi_descriptor(jit_context_t *ctx, int wasi_fd) {
    if (wasi_fd < 0) return 0;
    return get_native_fd(ctx, wasi_fd) >= 0;
}

static uint8_t stdio_filetype_native(int native_fd) {
#ifdef _WIN32
    return _isatty(native_fd) ? WASI_FILETYPE_CHARACTER_DEVICE : WASI_FILETYPE_UNKNOWN;
#else
    return isatty(native_fd) ? WASI_FILETYPE_CHARACTER_DEVICE : WASI_FILETYPE_UNKNOWN;
#endif
}

static int get_non_stdio_native_fd(jit_context_t *ctx, int wasi_fd, int *native_fd_out) {
    if (!ctx || !native_fd_out) return WASI_EBADF;
    if (is_stdio_fd(ctx, wasi_fd)) return WASI_EBADF;
    int native_fd = get_native_fd(ctx, wasi_fd);
    if (native_fd < 0) return WASI_EBADF;
    if (!ctx->fd_table || wasi_fd >= ctx->fd_table_size) return WASI_EBADF;
    *native_fd_out = native_fd;
    return WASI_ESUCCESS;
}

static int get_regular_file_native_fd(jit_context_t *ctx, int wasi_fd, int *native_fd_out) {
    if (!ctx || !native_fd_out) return WASI_EBADF;
    if (is_stdio_fd(ctx, wasi_fd)) return WASI_EBADF;
    if (is_preopen_fd(ctx, wasi_fd) || get_open_dir_path(ctx, wasi_fd)) return WASI_EBADF;
    int native_fd = get_native_fd(ctx, wasi_fd);
    if (native_fd < 0) return WASI_EBADF;
#ifndef _WIN32
    struct stat st;
    if (fstat(native_fd, &st) < 0) return WASI_EBADF;
    if (!S_ISREG(st.st_mode)) return WASI_EBADF;
#endif
    *native_fd_out = native_fd;
    return WASI_ESUCCESS;
}

// Descriptor adapter used by the shared MoonBit poll_oneoff implementation.
// Return values from resolve_fd are native fd (>= 0), immediate readiness (-2),
// missing descriptor rights (-3), or invalid descriptor/event pairing (-1).
MOONBIT_FFI_EXPORT int64_t wasmoon_jit_active_context_ptr(void) {
    return (int64_t)get_current_jit_context();
}

MOONBIT_FFI_EXPORT int wasmoon_jit_poll_resolve_fd(
    int64_t ctx_ptr,
    int wasi_fd,
    int event_type
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || wasi_fd < 0) return -1;

    int stdio_slot = stdio_slot_for_fd(ctx, wasi_fd);
    if (stdio_slot >= 0) {
        if ((stdio_slot == 0 && event_type != 1) ||
            (stdio_slot != 0 && event_type != 2)) {
            return -1;
        }
        if ((stdio_slot == 0 &&
             (ctx->wasi_stdin_use_buffer || ctx->wasi_stdin_callback)) ||
            (stdio_slot == 1 && ctx->wasi_stdout_capture) ||
            (stdio_slot == 2 && ctx->wasi_stderr_capture)) {
            return -2;
        }
        return get_native_fd(ctx, wasi_fd);
    }

    if (is_preopen_fd(ctx, wasi_fd) || get_open_dir_path(ctx, wasi_fd)) {
        return -1;
    }
    uint64_t direction_right = event_type == 1
        ? WASI_RIGHT_FD_READ
        : WASI_RIGHT_FD_WRITE;
    int rights_err = require_base_rights(
        ctx,
        wasi_fd,
        WASI_RIGHT_POLL_FD_READWRITE | direction_right
    );
    if (rights_err == WASI_ENOTCAPABLE) return -3;
    if (rights_err != WASI_ESUCCESS) return -1;
    return get_native_fd(ctx, wasi_fd);
}

static int64_t jit_poll_regular_file_remaining(int native_fd, int *is_eof) {
#ifdef _WIN32
    (void)native_fd;
    if (is_eof) *is_eof = 0;
    return 1;
#else
    struct stat st;
    if (fstat(native_fd, &st) < 0 || !S_ISREG(st.st_mode)) return -1;
    off_t position = lseek(native_fd, 0, SEEK_CUR);
    if (position < 0) return -1;
    if ((uint64_t)position >= (uint64_t)st.st_size) {
        if (is_eof) *is_eof = 1;
        return 0;
    }
    return (int64_t)((uint64_t)st.st_size - (uint64_t)position);
#endif
}

MOONBIT_FFI_EXPORT int64_t wasmoon_jit_poll_fd_read_nbytes(
    int64_t ctx_ptr,
    int wasi_fd
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return 0;
    if (stdio_slot_for_fd(ctx, wasi_fd) >= 0) return 1;
    int native_fd = get_native_fd(ctx, wasi_fd);
    if (native_fd < 0) return 0;

    int64_t remaining = jit_poll_regular_file_remaining(native_fd, NULL);
    if (remaining >= 0) return remaining;
#ifndef _WIN32
    int available = 0;
    if (ioctl(native_fd, FIONREAD, &available) == 0 && available >= 0) {
        return available;
    }
#endif
    return 1;
}

MOONBIT_FFI_EXPORT int wasmoon_jit_poll_fd_read_flags(
    int64_t ctx_ptr,
    int wasi_fd
) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || stdio_slot_for_fd(ctx, wasi_fd) >= 0) return 0;
    int native_fd = get_native_fd(ctx, wasi_fd);
    if (native_fd < 0) return 0;
    int is_eof = 0;
    jit_poll_regular_file_remaining(native_fd, &is_eof);
    return is_eof ? 0x01 : 0;
}

static int ensure_fd_metadata_arrays(jit_context_t *ctx) {
    if (ctx->fd_host_paths && ctx->fd_is_dir &&
        ctx->fd_rights_base && ctx->fd_rights_inheriting) return 1;
    if (!ctx->fd_table || ctx->fd_table_size <= 0) return 0;
    ctx->fd_host_paths = malloc(ctx->fd_table_size * sizeof(char*));
    ctx->fd_is_dir = malloc(ctx->fd_table_size * sizeof(uint8_t));
    ctx->fd_rights_base = malloc(ctx->fd_table_size * sizeof(uint64_t));
    ctx->fd_rights_inheriting = malloc(ctx->fd_table_size * sizeof(uint64_t));
    if (!ctx->fd_host_paths || !ctx->fd_is_dir ||
        !ctx->fd_rights_base || !ctx->fd_rights_inheriting) {
        free(ctx->fd_host_paths);
        free(ctx->fd_is_dir);
        free(ctx->fd_rights_base);
        free(ctx->fd_rights_inheriting);
        ctx->fd_host_paths = NULL;
        ctx->fd_is_dir = NULL;
        ctx->fd_rights_base = NULL;
        ctx->fd_rights_inheriting = NULL;
        return 0;
    }
    for (int i = 0; i < ctx->fd_table_size; i++) {
        ctx->fd_host_paths[i] = NULL;
        ctx->fd_is_dir[i] = 0;
        ctx->fd_rights_base[i] = 0;
        ctx->fd_rights_inheriting[i] = 0;
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
    uint64_t *new_rights_base = malloc(new_size * sizeof(uint64_t));
    uint64_t *new_rights_inheriting = malloc(new_size * sizeof(uint64_t));
    if (!new_table || !new_paths || !new_is_dir ||
        !new_rights_base || !new_rights_inheriting) {
        free(new_table);
        free(new_paths);
        free(new_is_dir);
        free(new_rights_base);
        free(new_rights_inheriting);
        return 0;
    }

    memcpy(new_table, ctx->fd_table, ctx->fd_table_size * sizeof(int));
    memcpy(new_paths, ctx->fd_host_paths, ctx->fd_table_size * sizeof(char*));
    memcpy(new_is_dir, ctx->fd_is_dir, ctx->fd_table_size * sizeof(uint8_t));
    memcpy(new_rights_base, ctx->fd_rights_base, ctx->fd_table_size * sizeof(uint64_t));
    memcpy(new_rights_inheriting, ctx->fd_rights_inheriting, ctx->fd_table_size * sizeof(uint64_t));
    for (int i = ctx->fd_table_size; i < new_size; i++) {
        new_table[i] = -1;
        new_paths[i] = NULL;
        new_is_dir[i] = 0;
        new_rights_base[i] = 0;
        new_rights_inheriting[i] = 0;
    }

    free(ctx->fd_table);
    free(ctx->fd_host_paths);
    free(ctx->fd_is_dir);
    free(ctx->fd_rights_base);
    free(ctx->fd_rights_inheriting);
    ctx->fd_table = new_table;
    ctx->fd_host_paths = new_paths;
    ctx->fd_is_dir = new_is_dir;
    ctx->fd_rights_base = new_rights_base;
    ctx->fd_rights_inheriting = new_rights_inheriting;
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
    if (wasi_fd < 0 || wasi_fd >= ctx->fd_table_size) return;
    if (ctx->fd_host_paths && ctx->fd_host_paths[wasi_fd]) {
        free(ctx->fd_host_paths[wasi_fd]);
        ctx->fd_host_paths[wasi_fd] = NULL;
    }
    if (ctx->fd_is_dir) ctx->fd_is_dir[wasi_fd] = 0;
    if (ctx->fd_rights_base) ctx->fd_rights_base[wasi_fd] = 0;
    if (ctx->fd_rights_inheriting) ctx->fd_rights_inheriting[wasi_fd] = 0;
}

static void set_fd_rights(
    jit_context_t *ctx,
    int wasi_fd,
    uint64_t rights_base,
    uint64_t rights_inheriting
) {
    if (!ctx || !ctx->fd_rights_base || !ctx->fd_rights_inheriting ||
        wasi_fd < 0 || wasi_fd >= ctx->fd_table_size) return;
    ctx->fd_rights_base[wasi_fd] = rights_base;
    ctx->fd_rights_inheriting[wasi_fd] = rights_inheriting;
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
static char* sanitize_guest_path(const char *path, int *wasi_errno) {
    if (wasi_errno) *wasi_errno = WASI_EINVAL;
    if (!path) return NULL;
    if (path[0] == '\0') {
        if (wasi_errno) *wasi_errno = WASI_ESUCCESS;
        return strdup("");
    }
    if (path[0] == '/') {
        if (wasi_errno) *wasi_errno = WASI_EPERM;
        return NULL;
    }

    size_t len = strlen(path);
    char *scratch = strdup(path);
    if (!scratch) {
        if (wasi_errno) *wasi_errno = WASI_ENOMEM;
        return NULL;
    }
    char **stack = malloc((len + 1) * sizeof(char *));
    if (!stack) {
        free(scratch);
        if (wasi_errno) *wasi_errno = WASI_ENOMEM;
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
                    if (wasi_errno) *wasi_errno = WASI_EPERM;
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
        if (wasi_errno) *wasi_errno = WASI_ENOMEM;
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
    if (wasi_errno) *wasi_errno = WASI_ESUCCESS;
    return out;
}

#ifndef _WIN32
static int path_is_within_base(const char *base_real, const char *target_real) {
    if (!base_real || !target_real) return 0;
    if (strcmp(base_real, "/") == 0) {
        return target_real[0] == '/';
    }
    size_t base_len = strlen(base_real);
    if (strncmp(base_real, target_real, base_len) != 0) return 0;
    char next = target_real[base_len];
    return next == '\0' || next == '/';
}

static int realpath_existing_parent(const char *path, char **out_real) {
    if (!path || !out_real) return 0;
    *out_real = NULL;

    char *scratch = strdup(path);
    if (!scratch) return 0;

    while (1) {
        errno = 0;
        char *resolved = realpath(scratch, NULL);
        if (resolved) {
            *out_real = resolved;
            free(scratch);
            return 1;
        }

        if (errno != ENOENT && errno != ENOTDIR) {
            break;
        }

        char *slash = strrchr(scratch, '/');
        if (!slash) {
            scratch[0] = '.';
            scratch[1] = '\0';
        } else if (slash == scratch) {
            scratch[1] = '\0';
        } else {
            *slash = '\0';
        }
    }

    free(scratch);
    return 0;
}

static int path_within_base(const char *base_path, const char *target_path) {
    if (!base_path || !target_path) return 0;

    char *base_real = realpath(base_path, NULL);
    if (!base_real) return 0;

    char *target_real = realpath(target_path, NULL);
    if (!target_real) {
        if (!realpath_existing_parent(target_path, &target_real)) {
            free(base_real);
            return 0;
        }
    }

    int ok = path_is_within_base(base_real, target_real);
    free(base_real);
    free(target_real);
    return ok;
}
#endif

static int check_mem_range(jit_context_t *ctx, int64_t ptr, size_t len) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return 0;
    if (ptr < 0) return 0;
    size_t mem_len = atomic_load_explicit(&ctx->memory0->current_length, memory_order_relaxed);
    size_t uptr = (size_t)ptr;
    if (uptr > mem_len) return 0;
    if (len > mem_len - uptr) return 0;
    return 1;
}

static int guest_bytes_contain_nul(const uint8_t *mem, uint32_t ptr, uint32_t len) {
    if (!mem || len == 0) return 0;
    return memchr(mem + ptr, '\0', (size_t)len) != NULL;
}

static int utf8_continuation(uint8_t b) {
    return b >= 0x80 && b <= 0xBF;
}

static int guest_bytes_valid_utf8(const uint8_t *mem, uint32_t ptr, uint32_t len) {
    if (!mem) return 0;
    uint32_t i = 0;
    while (i < len) {
        uint8_t b0 = mem[ptr + i];
        if (b0 < 0x80) {
            i += 1;
            continue;
        }
        if (b0 >= 0xC2 && b0 <= 0xDF) {
            if (i + 1 >= len) return 0;
            uint8_t b1 = mem[ptr + i + 1];
            if (!utf8_continuation(b1)) return 0;
            i += 2;
            continue;
        }
        if (b0 == 0xE0) {
            if (i + 2 >= len) return 0;
            uint8_t b1 = mem[ptr + i + 1];
            uint8_t b2 = mem[ptr + i + 2];
            if (b1 < 0xA0 || b1 > 0xBF || !utf8_continuation(b2)) return 0;
            i += 3;
            continue;
        }
        if ((b0 >= 0xE1 && b0 <= 0xEC) || (b0 >= 0xEE && b0 <= 0xEF)) {
            if (i + 2 >= len) return 0;
            uint8_t b1 = mem[ptr + i + 1];
            uint8_t b2 = mem[ptr + i + 2];
            if (!utf8_continuation(b1) || !utf8_continuation(b2)) return 0;
            i += 3;
            continue;
        }
        if (b0 == 0xED) {
            if (i + 2 >= len) return 0;
            uint8_t b1 = mem[ptr + i + 1];
            uint8_t b2 = mem[ptr + i + 2];
            if (b1 < 0x80 || b1 > 0x9F || !utf8_continuation(b2)) return 0;
            i += 3;
            continue;
        }
        if (b0 == 0xF0) {
            if (i + 3 >= len) return 0;
            uint8_t b1 = mem[ptr + i + 1];
            uint8_t b2 = mem[ptr + i + 2];
            uint8_t b3 = mem[ptr + i + 3];
            if (b1 < 0x90 || b1 > 0xBF ||
                !utf8_continuation(b2) ||
                !utf8_continuation(b3)) return 0;
            i += 4;
            continue;
        }
        if (b0 >= 0xF1 && b0 <= 0xF3) {
            if (i + 3 >= len) return 0;
            uint8_t b1 = mem[ptr + i + 1];
            uint8_t b2 = mem[ptr + i + 2];
            uint8_t b3 = mem[ptr + i + 3];
            if (!utf8_continuation(b1) ||
                !utf8_continuation(b2) ||
                !utf8_continuation(b3)) return 0;
            i += 4;
            continue;
        }
        if (b0 == 0xF4) {
            if (i + 3 >= len) return 0;
            uint8_t b1 = mem[ptr + i + 1];
            uint8_t b2 = mem[ptr + i + 2];
            uint8_t b3 = mem[ptr + i + 3];
            if (b1 < 0x80 || b1 > 0x8F ||
                !utf8_continuation(b2) ||
                !utf8_continuation(b3)) return 0;
            i += 4;
            continue;
        }
        return 0;
    }
    return 1;
}

static char *path_parent_no_trailing(const char *path) {
    if (!path) return NULL;
    char *scratch = strdup(path);
    if (!scratch) return NULL;

    size_t len = strlen(scratch);
    while (len > 1 && scratch[len - 1] == '/') {
        scratch[len - 1] = '\0';
        len--;
    }

    char *slash = strrchr(scratch, '/');
    if (!slash) {
        strcpy(scratch, ".");
        return scratch;
    }
    if (slash == scratch) {
        scratch[1] = '\0';
        return scratch;
    }
    *slash = '\0';
    return scratch;
}

// Resolve path relative to a directory fd and return WASI errno on failure.
static int resolve_path_with_errno(
    jit_context_t *ctx,
    int dir_fd,
    const char *path,
    int follow_leaf,
    char **out_path
) {
    if (!out_path) return WASI_EINVAL;
    if (!path) return WASI_EINVAL;
    if (path[0] == '\0') return WASI_ENOENT;
    *out_path = NULL;

    const char *base = get_preopen_path(ctx, dir_fd);
    if (!base) {
        base = get_open_dir_path(ctx, dir_fd);
        if (!base) return WASI_EBADF;
    }

    int sanitize_errno = WASI_ESUCCESS;
    char *rel = sanitize_guest_path(path, &sanitize_errno);
    if (!rel) return sanitize_errno;

    size_t base_len = strlen(base);
    size_t rel_len = strlen(rel);
    char *result = malloc(base_len + rel_len + 2);
    if (!result) {
        free(rel);
        return WASI_ENOMEM;
    }

    strcpy(result, base);
    if (rel[0] != '\0') {
        if (base_len > 0 && base[base_len - 1] != '/') {
            strcat(result, "/");
        }
        strcat(result, rel);
    }
    free(rel);

#ifdef _WIN32
    *out_path = result;
    return WASI_ESUCCESS;
#else
    const char *contain_target = result;
    char *contain_alloc = NULL;
    if (!follow_leaf && rel_len > 0) {
        contain_alloc = path_parent_no_trailing(result);
        if (!contain_alloc) {
            free(result);
            return WASI_ENOMEM;
        }
        contain_target = contain_alloc;
    }
    if (!path_within_base(base, contain_target)) {
        free(contain_alloc);
        free(result);
        return WASI_EPERM;
    }
    free(contain_alloc);
    *out_path = result;
    return WASI_ESUCCESS;
#endif
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
    } else if (!ctx->fd_host_paths || !ctx->fd_is_dir ||
               !ctx->fd_rights_base || !ctx->fd_rights_inheriting) {
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
    uint64_t *new_rights_base = malloc(new_size * sizeof(uint64_t));
    uint64_t *new_rights_inheriting = malloc(new_size * sizeof(uint64_t));
    if (!new_table || !new_paths || !new_is_dir ||
        !new_rights_base || !new_rights_inheriting) {
        free(new_table);
        free(new_paths);
        free(new_is_dir);
        free(new_rights_base);
        free(new_rights_inheriting);
        return -1;
    }

    memcpy(new_table, ctx->fd_table, ctx->fd_table_size * sizeof(int));
    memcpy(new_paths, ctx->fd_host_paths, ctx->fd_table_size * sizeof(char*));
    memcpy(new_is_dir, ctx->fd_is_dir, ctx->fd_table_size * sizeof(uint8_t));
    memcpy(new_rights_base, ctx->fd_rights_base, ctx->fd_table_size * sizeof(uint64_t));
    memcpy(new_rights_inheriting, ctx->fd_rights_inheriting, ctx->fd_table_size * sizeof(uint64_t));
    for (int i = ctx->fd_table_size; i < new_size; i++) {
        new_table[i] = -1;
        new_paths[i] = NULL;
        new_is_dir[i] = 0;
        new_rights_base[i] = 0;
        new_rights_inheriting[i] = 0;
    }
    free(ctx->fd_table);
    free(ctx->fd_host_paths);
    free(ctx->fd_is_dir);
    free(ctx->fd_rights_base);
    free(ctx->fd_rights_inheriting);
    ctx->fd_table = new_table;
    ctx->fd_host_paths = new_paths;
    ctx->fd_is_dir = new_is_dir;
    ctx->fd_rights_base = new_rights_base;
    ctx->fd_rights_inheriting = new_rights_inheriting;
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
#ifdef E2BIG
        case E2BIG: return 1;
#endif
#ifdef EACCES
        case EACCES: return 2;
#endif
#ifdef EAGAIN
        case EAGAIN: return 6;
#endif
#if defined(EWOULDBLOCK) && (!defined(EAGAIN) || EWOULDBLOCK != EAGAIN)
        case EWOULDBLOCK: return 6;
#endif
#ifdef EALREADY
        case EALREADY: return 7;
#endif
#ifdef EBADF
        case EBADF: return 8;
#endif
#ifdef EBUSY
        case EBUSY: return 10;
#endif
#ifdef ECANCELED
        case ECANCELED: return 11;
#endif
#ifdef ECHILD
        case ECHILD: return 12;
#endif
#ifdef ECONNABORTED
        case ECONNABORTED: return 13;
#endif
#ifdef ECONNREFUSED
        case ECONNREFUSED: return 14;
#endif
#ifdef ECONNRESET
        case ECONNRESET: return 15;
#endif
#if defined(EDEADLK)
        case EDEADLK: return 16;
#endif
#if defined(EDEADLOCK) && (!defined(EDEADLK) || EDEADLOCK != EDEADLK)
        case EDEADLOCK: return 16;
#endif
#ifdef EDESTADDRREQ
        case EDESTADDRREQ: return 17;
#endif
#ifdef EDOM
        case EDOM: return 18;
#endif
#ifdef EDQUOT
        case EDQUOT: return 19;
#endif
#ifdef EEXIST
        case EEXIST: return 20;
#endif
#ifdef EFAULT
        case EFAULT: return 21;
#endif
#ifdef EFBIG
        case EFBIG: return 22;
#endif
#ifdef EILSEQ
        case EILSEQ: return 25;
#endif
#ifdef EINPROGRESS
        case EINPROGRESS: return 26;
#endif
#ifdef EINTR
        case EINTR: return 27;
#endif
#ifdef EINVAL
        case EINVAL: return 28;
#endif
#ifdef EIO
        case EIO: return 29;
#endif
#ifdef EISCONN
        case EISCONN: return 30;
#endif
#ifdef EISDIR
        case EISDIR: return 31;
#endif
#ifdef ELOOP
        case ELOOP: return 32;
#endif
#ifdef EMFILE
        case EMFILE: return 33;
#endif
#ifdef EMLINK
        case EMLINK: return 34;
#endif
#ifdef EMSGSIZE
        case EMSGSIZE: return 35;
#endif
#ifdef ENAMETOOLONG
        case ENAMETOOLONG: return 37;
#endif
#ifdef ENETDOWN
        case ENETDOWN: return 38;
#endif
#ifdef ENETRESET
        case ENETRESET: return 39;
#endif
#ifdef ENETUNREACH
        case ENETUNREACH: return 40;
#endif
#ifdef ENFILE
        case ENFILE: return 41;
#endif
#ifdef ENOBUFS
        case ENOBUFS: return 42;
#endif
#ifdef ENODEV
        case ENODEV: return 43;
#endif
#ifdef ENOENT
        case ENOENT: return 44;
#endif
#ifdef ENOEXEC
        case ENOEXEC: return 45;
#endif
#ifdef ENOLCK
        case ENOLCK: return 46;
#endif
#ifdef ENOMEM
        case ENOMEM: return 48;
#endif
#ifdef ENOMSG
        case ENOMSG: return 49;
#endif
#ifdef ENOPROTOOPT
        case ENOPROTOOPT: return 50;
#endif
#ifdef ENOSPC
        case ENOSPC: return 51;
#endif
#ifdef ENOSYS
        case ENOSYS: return 52;
#endif
#ifdef ENOTCONN
        case ENOTCONN: return 53;
#endif
#ifdef ENOTDIR
        case ENOTDIR: return 54;
#endif
#ifdef ENOTEMPTY
        case ENOTEMPTY: return 55;
#endif
#ifdef ENOTRECOVERABLE
        case ENOTRECOVERABLE: return 56;
#endif
#ifdef ENOTSOCK
        case ENOTSOCK: return 57;
#endif
#ifdef ENOTSUP
        case ENOTSUP: return 58;
#endif
#if defined(EOPNOTSUPP) && (!defined(ENOTSUP) || EOPNOTSUPP != ENOTSUP)
        case EOPNOTSUPP: return 58;
#endif
#ifdef ENOTTY
        case ENOTTY: return 59;
#endif
#ifdef ENXIO
        case ENXIO: return 60;
#endif
#ifdef EOVERFLOW
        case EOVERFLOW: return 61;
#endif
#ifdef EPERM
        case EPERM: return 63;
#endif
#ifdef EPIPE
        case EPIPE: return 64;
#endif
#ifdef EPROTO
        case EPROTO: return 65;
#endif
#ifdef EPROTONOSUPPORT
        case EPROTONOSUPPORT: return 66;
#endif
#ifdef EPROTOTYPE
        case EPROTOTYPE: return 67;
#endif
#ifdef ERANGE
        case ERANGE: return 68;
#endif
#ifdef EROFS
        case EROFS: return 69;
#endif
#ifdef ESPIPE
        case ESPIPE: return 70;
#endif
#ifdef ESRCH
        case ESRCH: return 71;
#endif
#ifdef ETIMEDOUT
        case ETIMEDOUT: return 73;
#endif
#ifdef ETXTBSY
        case ETXTBSY: return 74;
#endif
#ifdef EXDEV
        case EXDEV: return 75;
#endif
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

static uint64_t preopen_directory_base_rights(void) {
    return WASI_RIGHT_PATH_CREATE_DIRECTORY |
        WASI_RIGHT_PATH_CREATE_FILE |
        WASI_RIGHT_PATH_LINK_SOURCE |
        WASI_RIGHT_PATH_LINK_TARGET |
        WASI_RIGHT_PATH_OPEN |
        WASI_RIGHT_FD_READDIR |
        WASI_RIGHT_PATH_READLINK |
        WASI_RIGHT_PATH_RENAME_SOURCE |
        WASI_RIGHT_PATH_RENAME_TARGET |
        WASI_RIGHT_PATH_SYMLINK |
        WASI_RIGHT_PATH_REMOVE_DIRECTORY |
        WASI_RIGHT_PATH_UNLINK_FILE |
        WASI_RIGHT_PATH_FILESTAT_GET |
        WASI_RIGHT_PATH_FILESTAT_SET_TIMES |
        WASI_RIGHT_FD_FILESTAT_GET |
        WASI_RIGHT_FD_FILESTAT_SET_TIMES;
}

static uint64_t preopen_directory_inheriting_rights(void) {
    uint64_t base = preopen_directory_base_rights();
    return base |
        WASI_RIGHT_FD_DATASYNC |
        WASI_RIGHT_FD_READ |
        WASI_RIGHT_FD_SEEK |
        WASI_RIGHT_FD_FDSTAT_SET_FLAGS |
        WASI_RIGHT_FD_SYNC |
        WASI_RIGHT_FD_TELL |
        WASI_RIGHT_FD_WRITE |
        WASI_RIGHT_FD_ADVISE |
        WASI_RIGHT_FD_ALLOCATE |
        WASI_RIGHT_FD_FILESTAT_GET |
        WASI_RIGHT_FD_FILESTAT_SET_SIZE |
        WASI_RIGHT_FD_FILESTAT_SET_TIMES |
        WASI_RIGHT_POLL_FD_READWRITE;
}

#ifndef _WIN32
static uint16_t wasi_fdflags_from_native(int native_fd) {
    uint16_t flags = 0;
    int native_flags = fcntl(native_fd, F_GETFL);
    if (native_flags < 0) return flags;

#ifdef O_APPEND
    if (native_flags & O_APPEND) flags |= 0x01; // APPEND
#endif
#ifdef O_DSYNC
    if (native_flags & O_DSYNC) flags |= 0x02; // DSYNC
#endif
#ifdef O_NONBLOCK
    if (native_flags & O_NONBLOCK) flags |= 0x04; // NONBLOCK
#endif
#ifdef O_RSYNC
    if (native_flags & O_RSYNC) flags |= 0x08; // RSYNC
#endif
#ifdef O_SYNC
    if (native_flags & O_SYNC) flags |= 0x10; // SYNC
#endif

    return flags;
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

static int first_non_empty_iov(
    jit_context_t *ctx,
    uint8_t *mem,
    uint32_t iovs_u,
    uint32_t iovs_len_u,
    uint32_t *buf_ptr_out,
    uint32_t *buf_len_out
) {
    for (uint32_t i = 0; i < iovs_len_u; i++) {
        uint32_t buf_ptr = *(uint32_t *)(mem + iovs_u + i * 8);
        uint32_t buf_len = *(uint32_t *)(mem + iovs_u + i * 8 + 4);
        if (buf_len == 0) continue;
        if (!check_mem_range(ctx, buf_ptr, (size_t)buf_len)) return -1;
        *buf_ptr_out = buf_ptr;
        *buf_len_out = buf_len;
        return 1;
    }
    return 0;
}

static int validate_iovecs(
    jit_context_t *ctx,
    uint8_t *mem,
    uint32_t iovs_u,
    uint32_t iovs_len_u
) {
    for (uint32_t i = 0; i < iovs_len_u; i++) {
        uint32_t buf_ptr = *(uint32_t *)(mem + iovs_u + i * 8);
        uint32_t buf_len = *(uint32_t *)(mem + iovs_u + i * 8 + 4);
        if (!check_mem_range(ctx, buf_ptr, (size_t)buf_len)) return 0;
    }
    return 1;
}

static int invalid_lookupflags(int32_t flags) {
    return (flags & ~0x01) != 0;
}

static int invalid_sock_accept_fdflags(int32_t flags) {
    return (flags & ~0x1f) != 0;
}

static int invalid_sock_recv_riflags(int32_t ri_flags) {
    return (ri_flags & ~0x03) != 0;
}

static int invalid_sock_shutdown_sdflags(int32_t how) {
    return (how & ~0x03) != 0;
}

static int invalid_proc_raise_signal(int64_t sig) {
    return sig < 0 || sig > 30;
}

static int32_t trap_invalid_wasi_abi_arg(void) {
    if (g_trap_active) {
        g_trap_code = 3; // unreachable
        siglongjmp(g_trap_jmp_buf, 1);
    }
    return WASI_EINVAL;
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
    int stdio_slot = stdio_slot_for_fd(ctx, wasi_fd);
    if (stdio_slot == 0) {
        if (get_native_fd(ctx, wasi_fd) < 0) return WASI_EBADF;
        return WASI_EBADF;
    }
    if (stdio_slot == 1 || stdio_slot == 2) {
        if (get_native_fd(ctx, wasi_fd) < 0) return WASI_EBADF;
    } else if (is_preopen_fd(ctx, wasi_fd) || get_open_dir_path(ctx, wasi_fd)) {
        return WASI_EBADF;
    }
    int use_stdout_capture = (stdio_slot == 1 && ctx->wasi_stdout_capture);
    int use_stderr_capture = (stdio_slot == 2 && ctx->wasi_stderr_capture);
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

    if (!validate_iovecs(ctx, mem, iovs_u, iovs_len_u)) return WASI_EFAULT;

    uint32_t total = 0;
    for (uint32_t i = 0; i < iovs_len_u; i++) {
        uint32_t buf_ptr = *(uint32_t *)(mem + iovs_u + i * 8);
        uint32_t buf_len = *(uint32_t *)(mem + iovs_u + i * 8 + 4);
        if (buf_len == 0) continue;
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
            if ((uint32_t)n < buf_len) break;
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
    int stdio_slot = stdio_slot_for_fd(ctx, wasi_fd);
    if (stdio_slot == 0 && get_native_fd(ctx, wasi_fd) < 0) return WASI_EBADF;
    if (stdio_slot == 1 || stdio_slot == 2) return WASI_EBADF;
    if (stdio_slot < 0 && (is_preopen_fd(ctx, wasi_fd) || get_open_dir_path(ctx, wasi_fd))) {
        return WASI_EBADF;
    }
    uint32_t iovs_u = (uint32_t)iovs;
    uint32_t iovs_len_u = (uint32_t)iovs_len;
    uint32_t nread_ptr_u = (uint32_t)nread_ptr;
    if (!check_mem_range(ctx, iovs_u, (size_t)iovs_len_u * 8)) return WASI_EFAULT;
    if (!check_mem_range(ctx, nread_ptr_u, 4)) return WASI_EFAULT;

    uint32_t buf_ptr = 0;
    uint32_t buf_len = 0;
    int first_iov = first_non_empty_iov(ctx, mem, iovs_u, iovs_len_u, &buf_ptr, &buf_len);
    if (first_iov < 0) return WASI_EFAULT;

    uint32_t total = 0;
    if (first_iov == 0) {
        *(uint32_t *)(mem + nread_ptr_u) = 0;
        return WASI_ESUCCESS;
    }
    if (stdio_slot == 0) {
        if (ctx->wasi_stdin_use_buffer) {
            size_t available = 0;
            if (ctx->wasi_stdin_len > ctx->wasi_stdin_offset) {
                available = ctx->wasi_stdin_len - ctx->wasi_stdin_offset;
            }
            size_t to_copy = available < (size_t)buf_len ? available : (size_t)buf_len;
            if (to_copy > 0 && ctx->wasi_stdin_buf) {
                memcpy(
                    mem + buf_ptr,
                    ctx->wasi_stdin_buf + ctx->wasi_stdin_offset,
                    to_copy
                );
            }
            ctx->wasi_stdin_offset += to_copy;
            total = (uint32_t)to_copy;
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
            size_t to_copy = input_len < (size_t)buf_len ? input_len : (size_t)buf_len;
            if (to_copy > 0 && input) {
                memcpy(mem + buf_ptr, input, to_copy);
            }
            total = (uint32_t)to_copy;
            *(uint32_t *)(mem + nread_ptr_u) = total;
            if (input) moonbit_decref(input);
            return WASI_ESUCCESS;
        }
    }

    int native_fd = get_native_fd(ctx, wasi_fd);
    if (native_fd < 0) return WASI_EBADF;
    if (buf_len > 0) {
#ifdef _WIN32
        int n = _read(native_fd, mem + buf_ptr, buf_len);
#else
        ssize_t n = read(native_fd, mem + buf_ptr, buf_len);
#endif
        if (n < 0) return errno_to_wasi(errno);
        total = (uint32_t)n;
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
    if (wasi_fd < 0) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, wasi_fd);
    if (native_fd < 0) return WASI_EBADF;

    int stdio_slot = stdio_slot_for_fd(ctx, wasi_fd);
    if (stdio_slot >= 0) {
        if (native_fd > 2) {
#ifdef _WIN32
            _close(native_fd);
#else
            close(native_fd);
#endif
        }
        if (ctx->fd_table && wasi_fd < ctx->fd_table_size) {
            ctx->fd_table[wasi_fd] = -1;
        }
        clear_fd_metadata(ctx, wasi_fd);
        clear_stdio_slot(ctx, stdio_slot);
        return WASI_ESUCCESS;
    }

    if (wasi_fd >= 0 && ctx->fd_table && wasi_fd < ctx->fd_table_size) {
        ctx->fd_table[wasi_fd] = -1;
    }
    clear_fd_metadata(ctx, wasi_fd);

#ifdef _WIN32
    _close(native_fd);
#else
    close(native_fd);
#endif
    return WASI_ESUCCESS;
}

// fd_seek: (fd, offset, whence, newoffset) -> errno
static int64_t wasi_fd_seek_impl(
    jit_context_t *ctx,
    int64_t fd, int64_t offset, int64_t whence, int64_t newoffset_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    if (whence < 0 || whence > 2) return trap_invalid_wasi_abi_arg();

    int wasi_fd = (int)fd;
    if (wasi_fd < 0) return WASI_EBADF;
    int stdio_slot = stdio_slot_for_fd(ctx, wasi_fd);
    if (stdio_slot >= 0) {
        if (get_native_fd(ctx, wasi_fd) < 0) return WASI_EBADF;
        return WASI_ESPIPE; // stdio not seekable
    }
    if (is_preopen_fd(ctx, wasi_fd) || get_open_dir_path(ctx, wasi_fd)) return WASI_EBADF;
    int native_fd = get_native_fd(ctx, wasi_fd);
    if (native_fd < 0) return WASI_EBADF;
    uint32_t newoffset_ptr_u = (uint32_t)newoffset_ptr;
    if (!check_mem_range(ctx, newoffset_ptr_u, 8)) return WASI_EFAULT;
    uint32_t whence_u = (uint32_t)whence;

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
    int native_fd = -1;
    int err = get_regular_file_native_fd(ctx, (int32_t)fd, &native_fd);
    if (err != WASI_ESUCCESS) return err;

#ifdef _WIN32
    return WASI_ESUCCESS; // No sync on Windows
#else
    if (fsync(native_fd) < 0) return errno_to_wasi(errno);
    return WASI_ESUCCESS;
#endif
}

// fd_datasync: (fd) -> errno
static int64_t wasi_fd_datasync_impl(
    jit_context_t *ctx, int64_t fd
) {
    if (!ctx) return WASI_EBADF;
    int native_fd = -1;
    int err = get_regular_file_native_fd(ctx, (int32_t)fd, &native_fd);
    if (err != WASI_ESUCCESS) return err;

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
    jit_context_t *ctx,
    int64_t fd, int64_t fdstat_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t fdstat_ptr_u = (uint32_t)fdstat_ptr;
    if (!check_mem_range(ctx, fdstat_ptr_u, 24)) return WASI_EFAULT;

    uint8_t *mem = ctx->memory0->base;
    int wasi_fd = (int)fd;

    uint8_t filetype;
    uint16_t flags = 0;
    uint64_t rights_base = 0;
    uint64_t rights_inheriting = 0;
    int stdio_slot = stdio_slot_for_fd(ctx, wasi_fd);
    if (stdio_slot >= 0) {
        int native_fd = get_native_fd(ctx, wasi_fd);
        if (native_fd < 0) return WASI_EBADF;
        filetype = stdio_filetype_native(native_fd);
        rights_base = (stdio_slot == 0) ? WASI_RIGHT_FD_READ : WASI_RIGHT_FD_WRITE;
        rights_base |= WASI_RIGHT_POLL_FD_READWRITE;
        rights_inheriting = rights_base;
    } else if (is_preopen_fd(ctx, wasi_fd)) {
        filetype = WASI_FILETYPE_DIRECTORY;
        if (!ctx->fd_rights_base || !ctx->fd_rights_inheriting ||
            wasi_fd >= ctx->fd_table_size) return WASI_EBADF;
        rights_base = ctx->fd_rights_base[wasi_fd];
        rights_inheriting = ctx->fd_rights_inheriting[wasi_fd];
    } else {
        int native_fd = get_native_fd(ctx, wasi_fd);
        if (native_fd < 0) return WASI_EBADF;
#ifndef _WIN32
        struct stat st;
        if (fstat(native_fd, &st) < 0) return errno_to_wasi(errno);
        filetype = mode_to_filetype(st.st_mode);
        flags = wasi_fdflags_from_native(native_fd);
#else
        filetype = WASI_FILETYPE_REGULAR_FILE;
#endif
        if (!ctx->fd_rights_base || !ctx->fd_rights_inheriting ||
            wasi_fd >= ctx->fd_table_size) return WASI_EBADF;
        rights_base = ctx->fd_rights_base[wasi_fd];
        rights_inheriting = ctx->fd_rights_inheriting[wasi_fd];
    }

    // fdstat: filetype(1) + pad(1) + flags(2) + pad(4) + rights_base(8) + rights_inheriting(8)
    mem[fdstat_ptr_u] = filetype;
    mem[fdstat_ptr_u + 1] = 0;
    *(uint16_t *)(mem + fdstat_ptr_u + 2) = flags;
    *(uint32_t *)(mem + fdstat_ptr_u + 4) = 0;
    *(uint64_t *)(mem + fdstat_ptr_u + 8) = rights_base;
    *(uint64_t *)(mem + fdstat_ptr_u + 16) = rights_inheriting;
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

    int idx = preopen_index_for_fd(ctx, wasi_fd);
    if (idx < 0) return WASI_EBADF;
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
    if (!is_valid_wasi_descriptor(ctx, wasi_fd)) return WASI_EBADF;
    if (!is_preopen_fd(ctx, wasi_fd)) return WASI_ENOTDIR;

    int idx = preopen_index_for_fd(ctx, wasi_fd);
    if (idx < 0) return WASI_ENOTDIR;
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
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    if (invalid_lookupflags((int32_t)dirflags)) return trap_invalid_wasi_abi_arg();
    if ((oflags & ~0x0f) != 0) return trap_invalid_wasi_abi_arg();
    if ((fdflags & ~0x1f) != 0) return trap_invalid_wasi_abi_arg();
    if ((oflags & 0x02) && ((oflags & 0x01) || (oflags & 0x04) || (oflags & 0x08))) {
        return WASI_EINVAL;
    }
    uint32_t path_ptr_u = (uint32_t)path_ptr;
    uint32_t path_len_u = (uint32_t)path_len;
    uint32_t opened_fd_ptr_u = (uint32_t)opened_fd_ptr;
    if (!check_mem_range(ctx, path_ptr_u, (size_t)path_len_u)) {
        return WASI_EFAULT;
    }
    if (guest_bytes_contain_nul(ctx->memory0->base, path_ptr_u, path_len_u)) {
        return WASI_EINVAL;
    }
    if (!guest_bytes_valid_utf8(ctx->memory0->base, path_ptr_u, path_len_u)) {
        return WASI_EILSEQ;
    }
    if (!check_mem_range(ctx, opened_fd_ptr_u, 4)) return WASI_EFAULT;

    int dirfd_i = (int)dir_fd;
    if (is_stdio_fd(ctx, dirfd_i)) {
        if (get_native_fd(ctx, dirfd_i) < 0) return WASI_EBADF;
        return WASI_EBADF;
    }
    if (!is_preopen_fd(ctx, dirfd_i) && !get_open_dir_path(ctx, dirfd_i)) {
        if (get_native_fd(ctx, dirfd_i) >= 0) return WASI_ENOTDIR;
        return WASI_EBADF;
    }
    if (!ctx->fd_rights_inheriting || dirfd_i < 0 ||
        dirfd_i >= ctx->fd_table_size) return WASI_EBADF;
    uint64_t effective_rights_base = (uint64_t)rights_base;
    uint64_t effective_rights_inheriting = (uint64_t)rights_inh;
    if ((effective_rights_base & ~WASI_RIGHTS_ALL_VALID) != 0 ||
        (effective_rights_inheriting & ~WASI_RIGHTS_ALL_VALID) != 0) {
        return WASI_EINVAL;
    }
    uint64_t parent_rights_inheriting = ctx->fd_rights_inheriting[dirfd_i];
    if ((effective_rights_base & parent_rights_inheriting) != effective_rights_base ||
        (effective_rights_inheriting & parent_rights_inheriting) != effective_rights_inheriting) {
        return WASI_ENOTCAPABLE;
    }
    if (((int64_t)fdflags & 0x1A) != 0) { // DSYNC/RSYNC/SYNC
        return WASI_ENOTSUP;
    }
    // Read path from memory
    char *path = malloc((size_t)path_len_u + 1);
    if (!path) return WASI_ENOMEM;
    memcpy(path, ctx->memory0->base + path_ptr_u, (size_t)path_len_u);
    path[path_len_u] = '\0';
    int has_trailing_slash = path_len_u > 0 && path[path_len_u - 1] == '/';
    int follow_symlink = (dirflags & 0x01) != 0;

    // Resolve full path
    char *full_path = NULL;
    int path_errno = resolve_path_with_errno(
        ctx,
        (int)dir_fd,
        path,
        ((dirflags & 0x01) != 0),
        &full_path
    );
    free(path);
    if (path_errno != WASI_ESUCCESS) return path_errno;

#ifndef _WIN32
    // Build open flags
    int flags = 0;
    if (oflags & 0x01) flags |= O_CREAT;
    if (oflags & 0x02) flags |= O_DIRECTORY;
    if (oflags & 0x04) flags |= O_EXCL;
    if (oflags & 0x08) flags |= O_TRUNC;
    if (fdflags & 0x01) flags |= O_APPEND;
#ifdef O_NOFOLLOW
    if (!follow_symlink) flags |= O_NOFOLLOW;
#endif
    int wants_read = (((uint64_t)rights_base) & WASI_RIGHT_FD_READ) != 0;
    int wants_write = (((uint64_t)rights_base) & WASI_RIGHT_FD_WRITE) != 0;
    int requires_write = wants_write || (oflags & 0x01) || (oflags & 0x08) || (fdflags & 0x01);
    if (wants_read && requires_write) flags |= O_RDWR;
    else if (requires_write) flags |= O_WRONLY;
    else flags |= O_RDONLY;

    const char *open_path = full_path;
    char *open_path_alloc = NULL;
    if (has_trailing_slash) {
        size_t full_len = strlen(full_path);
        open_path_alloc = malloc(full_len + 2);
        if (!open_path_alloc) {
            free(full_path);
            return WASI_ENOMEM;
        }
        memcpy(open_path_alloc, full_path, full_len);
        open_path_alloc[full_len] = '/';
        open_path_alloc[full_len + 1] = '\0';
        open_path = open_path_alloc;
    }

    int native_fd = open(open_path, flags, 0644);
    if (open_path_alloc) free(open_path_alloc);
    if (native_fd < 0) {
        if (has_trailing_slash && errno == ENOTDIR) {
            free(full_path);
            return WASI_ENOENT;
        }
        free(full_path);
        return errno_to_wasi(errno);
    }

    struct stat st;
    if (fstat(native_fd, &st) < 0) {
        close(native_fd);
        free(full_path);
        return errno_to_wasi(errno);
    }
    int is_dir = S_ISDIR(st.st_mode) ? 1 : 0;

    int wasi_fd = alloc_wasi_fd(ctx, native_fd);
    if (wasi_fd < 0) {
        close(native_fd);
        free(full_path);
        return WASI_ENOMEM;
    }

    set_fd_metadata(ctx, wasi_fd, full_path, is_dir);
    set_fd_rights(
        ctx,
        wasi_fd,
        effective_rights_base,
        effective_rights_inheriting
    );
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
    if (guest_bytes_contain_nul(ctx->memory0->base, path_ptr_u, path_len_u)) {
        return WASI_EINVAL;
    }
    if (!guest_bytes_valid_utf8(ctx->memory0->base, path_ptr_u, path_len_u)) {
        return WASI_EILSEQ;
    }

    char *path = malloc((size_t)path_len_u + 1);
    if (!path) return WASI_ENOMEM;
    memcpy(path, ctx->memory0->base + path_ptr_u, (size_t)path_len_u);
    path[path_len_u] = '\0';

    char *full_path = NULL;
    int path_errno = resolve_path_with_errno(ctx, (int)dir_fd, path, 0, &full_path);
    free(path);
    if (path_errno != WASI_ESUCCESS) return path_errno;

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
    if (guest_bytes_contain_nul(ctx->memory0->base, path_ptr_u, path_len_u)) {
        return WASI_EINVAL;
    }
    if (!guest_bytes_valid_utf8(ctx->memory0->base, path_ptr_u, path_len_u)) {
        return WASI_EILSEQ;
    }

    char *path = malloc((size_t)path_len_u + 1);
    if (!path) return WASI_ENOMEM;
    memcpy(path, ctx->memory0->base + path_ptr_u, (size_t)path_len_u);
    path[path_len_u] = '\0';

    char *full_path = NULL;
    int path_errno = resolve_path_with_errno(ctx, (int)dir_fd, path, 0, &full_path);
    free(path);
    if (path_errno != WASI_ESUCCESS) return path_errno;

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
    if (guest_bytes_contain_nul(ctx->memory0->base, path_ptr_u, path_len_u)) {
        return WASI_EINVAL;
    }
    if (!guest_bytes_valid_utf8(ctx->memory0->base, path_ptr_u, path_len_u)) {
        return WASI_EILSEQ;
    }

    char *path = malloc((size_t)path_len_u + 1);
    if (!path) return WASI_ENOMEM;
    memcpy(path, ctx->memory0->base + path_ptr_u, (size_t)path_len_u);
    path[path_len_u] = '\0';

    char *full_path = NULL;
    int path_errno = resolve_path_with_errno(ctx, (int)dir_fd, path, 0, &full_path);
    free(path);
    if (path_errno != WASI_ESUCCESS) return path_errno;

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
    if (guest_bytes_contain_nul(ctx->memory0->base, old_path_ptr_u, old_path_len_u) ||
        guest_bytes_contain_nul(ctx->memory0->base, new_path_ptr_u, new_path_len_u)) {
        return WASI_EINVAL;
    }
    if (!guest_bytes_valid_utf8(ctx->memory0->base, old_path_ptr_u, old_path_len_u) ||
        !guest_bytes_valid_utf8(ctx->memory0->base, new_path_ptr_u, new_path_len_u)) {
        return WASI_EILSEQ;
    }

    char *old_path = malloc((size_t)old_path_len_u + 1);
    char *new_path = malloc((size_t)new_path_len_u + 1);
    if (!old_path || !new_path) {
        free(old_path);
        free(new_path);
        return WASI_ENOMEM;
    }

    memcpy(old_path, ctx->memory0->base + old_path_ptr_u, (size_t)old_path_len_u);
    old_path[old_path_len_u] = '\0';
    memcpy(new_path, ctx->memory0->base + new_path_ptr_u, (size_t)new_path_len_u);
    new_path[new_path_len_u] = '\0';

    char *old_full = NULL;
    int old_errno = resolve_path_with_errno(ctx, (int)old_fd, old_path, 0, &old_full);
    char *new_full = NULL;
    int new_errno = resolve_path_with_errno(ctx, (int)new_fd, new_path, 0, &new_full);
    free(old_path);
    free(new_path);

    if (old_errno != WASI_ESUCCESS || new_errno != WASI_ESUCCESS) {
        free(old_full);
        free(new_full);
        if (old_errno != WASI_ESUCCESS) return old_errno;
        return new_errno;
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
    int stdio_slot = stdio_slot_for_fd(ctx, wasi_fd);
    if (stdio_slot >= 0) {
        int native_fd = get_native_fd(ctx, wasi_fd);
        if (native_fd < 0) return WASI_EBADF;
        memset(mem + buf_ptr_u, 0, 64);
        mem[buf_ptr_u + 16] = stdio_filetype_native(native_fd);
        *(uint64_t *)(mem + buf_ptr_u + 24) = 0; // nlink
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
    int native_fd = -1;
    int err = get_regular_file_native_fd(ctx, (int32_t)fd, &native_fd);
    if (err != WASI_ESUCCESS) return err;

#ifndef _WIN32
    if (ftruncate(native_fd, size) < 0) return errno_to_wasi(errno);
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
    if (clock_id < 0 || clock_id > 3) return trap_invalid_wasi_abi_arg();
    uint32_t time_ptr_u = (uint32_t)time_ptr;
    if (!check_mem_range(ctx, time_ptr_u, 8)) return WASI_EFAULT;

    int64_t time_ns = 0;
    // WASI clock IDs: 0=REALTIME, 1=MONOTONIC, 2=PROCESS_CPUTIME_ID, 3=THREAD_CPUTIME_ID.
    // Match wasmtime p1: CPU-time clocks are unsupported in preview1 and return EBADF.
    if (clock_id == 0 || clock_id == 1) {
#ifdef _WIN32
        FILETIME ft;
        GetSystemTimeAsFileTime(&ft);
        uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
        time_ns = (int64_t)((t - 116444736000000000ULL) * 100);
#else
        struct timespec ts;
        clockid_t clk = (clock_id == 0) ? CLOCK_REALTIME : CLOCK_MONOTONIC;
        clock_gettime(clk, &ts);
        time_ns = (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
    } else if (clock_id == 2 || clock_id == 3) {
        return WASI_EBADF;
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
    if (clock_id < 0 || clock_id > 3) return trap_invalid_wasi_abi_arg();
    uint32_t resolution_ptr_u = (uint32_t)resolution_ptr;
    if (!check_mem_range(ctx, resolution_ptr_u, 8)) return WASI_EFAULT;

    // WASI clock IDs: 0=REALTIME, 1=MONOTONIC, 2=PROCESS_CPUTIME_ID, 3=THREAD_CPUTIME_ID.
    // Match wasmtime p1: CPU-time clocks return EBADF.
    if (clock_id == 2 || clock_id == 3) return WASI_EBADF;
#ifdef _WIN32
    if (clock_id == 0) {
        *(int64_t *)(ctx->memory0->base + resolution_ptr_u) = 1000000; // 1ms fallback
        return WASI_ESUCCESS;
    }
    LARGE_INTEGER freq;
    if (!QueryPerformanceFrequency(&freq) || freq.QuadPart <= 0) return errno_to_wasi(EINVAL);
    *(int64_t *)(ctx->memory0->base + resolution_ptr_u) = (int64_t)(1000000000LL / freq.QuadPart);
    return WASI_ESUCCESS;
#else
    struct timespec ts;
    clockid_t clk = (clock_id == 0) ? CLOCK_REALTIME : CLOCK_MONOTONIC;
    if (clock_getres(clk, &ts) != 0) return errno_to_wasi(errno);
    *(int64_t *)(ctx->memory0->base + resolution_ptr_u) =
        (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
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
    if (!fill_random_bytes(mem + buf_ptr_u, (size_t)buf_len_u)) return errno_to_wasi(errno);
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
    if (invalid_proc_raise_signal(sig)) return trap_invalid_wasi_abi_arg();
    return WASI_ENOTSUP;
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

    // Match wasmtime:
    // - fd_pread(stdin) -> ESPIPE
    // - fd_pread(stdout/stderr) -> EBADF
    int stdio_slot = stdio_slot_for_fd(ctx, fd);
    if (stdio_slot == 0) {
        if (get_native_fd(ctx, fd) < 0) return WASI_EBADF;
        return WASI_ESPIPE;
    }
    if (stdio_slot == 1 || stdio_slot == 2) {
        if (get_native_fd(ctx, fd) < 0) return WASI_EBADF;
        return WASI_EBADF;
    }
    if (is_preopen_fd(ctx, fd) || get_open_dir_path(ctx, fd)) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;

#ifndef _WIN32
    uint32_t buf_ptr = 0;
    uint32_t buf_len = 0;
    int first_iov = first_non_empty_iov(ctx, mem, iovs_ptr_u, iovs_len_u, &buf_ptr, &buf_len);
    if (first_iov < 0) return WASI_EFAULT;
    if (first_iov == 0) {
        *(uint32_t *)(mem + nread_ptr_u) = 0;
        return WASI_ESUCCESS;
    }
    ssize_t n = pread(native_fd, mem + buf_ptr, buf_len, offset);
    if (n < 0) return errno_to_wasi(errno);
    *(uint32_t *)(mem + nread_ptr_u) = (uint32_t)n;
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

    // Match wasmtime:
    // - fd_pwrite(stdout/stderr) -> ESPIPE
    // - fd_pwrite(stdin) -> EBADF
    int stdio_slot = stdio_slot_for_fd(ctx, fd);
    if (stdio_slot == 1 || stdio_slot == 2) {
        if (get_native_fd(ctx, fd) < 0) return WASI_EBADF;
        return WASI_ESPIPE;
    }
    if (stdio_slot == 0) {
        if (get_native_fd(ctx, fd) < 0) return WASI_EBADF;
        return WASI_EBADF;
    }
    if (is_preopen_fd(ctx, fd) || get_open_dir_path(ctx, fd)) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;

#ifndef _WIN32
    uint32_t buf_ptr = 0;
    uint32_t buf_len = 0;
    int first_iov = first_non_empty_iov(ctx, mem, iovs_ptr_u, iovs_len_u, &buf_ptr, &buf_len);
    if (first_iov < 0) return WASI_EFAULT;
    if (first_iov == 0) {
        *(uint32_t *)(mem + nwritten_ptr_u) = 0;
        return WASI_ESUCCESS;
    }
    ssize_t n = pwrite(native_fd, mem + buf_ptr, buf_len, offset);
    if (n < 0) return errno_to_wasi(errno);
    *(uint32_t *)(mem + nwritten_ptr_u) = (uint32_t)n;
    return WASI_ESUCCESS;
#else
    return WASI_ENOSYS;
#endif
}

static uint32_t write_readdir_entry_with_truncation(
    uint8_t *buf,
    uint32_t buf_len,
    uint32_t used,
    uint64_t d_next,
    uint64_t d_ino,
    uint8_t d_type,
    const char *name,
    size_t name_len,
    int *entry_complete
) {
    *entry_complete = 0;
    if (used >= buf_len) return used;

    uint8_t header[24];
    memset(header, 0, sizeof(header));
    uint64_t next_le = d_next;
    uint64_t ino_le = d_ino;
    uint32_t namelen_le = (uint32_t)name_len;
    memcpy(header + 0, &next_le, sizeof(next_le));
    memcpy(header + 8, &ino_le, sizeof(ino_le));
    memcpy(header + 16, &namelen_le, sizeof(namelen_le));
    header[20] = d_type;

    uint32_t remain = buf_len - used;
    uint32_t header_write = remain < 24 ? remain : 24;
    memcpy(buf + used, header, header_write);
    used += header_write;
    if (header_write < 24) return used;

    if (used >= buf_len) return used;
    uint32_t name_cap = buf_len - used;
    uint32_t name_write = (uint32_t)(name_len < (size_t)name_cap ? name_len : (size_t)name_cap);
    if (name_write > 0) memcpy(buf + used, name, name_write);
    used += name_write;
    *entry_complete = (name_write == name_len);
    return used;
}

// fd_readdir: Read directory entries
static int32_t wasi_fd_readdir_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t buf_ptr, int32_t buf_len, int64_t cookie, int32_t bufused_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    if (is_stdio_fd(ctx, fd)) return WASI_EBADF;
    uint8_t *mem = ctx->memory0->base;
    uint32_t buf_ptr_u = (uint32_t)buf_ptr;
    uint32_t buf_len_u = (uint32_t)buf_len;
    uint32_t bufused_ptr_u = (uint32_t)bufused_ptr;
    if (!check_mem_range(ctx, buf_ptr_u, (size_t)buf_len_u)) return WASI_EFAULT;
    if (!check_mem_range(ctx, bufused_ptr_u, 4)) return WASI_EFAULT;

#ifndef _WIN32
    DIR *dir = NULL;
    if (!is_preopen_fd(ctx, fd) && !get_open_dir_path(ctx, fd)) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;
    int dir_fd = dup(native_fd);
    if (dir_fd < 0) return errno_to_wasi(errno);
    dir = fdopendir(dir_fd);
    if (!dir) {
        close(dir_fd);
        return errno_to_wasi(errno);
    }

    // Read entries into buffer. Match wasmtime's cookie stream:
    // 0 => ".", 1 => "..", 2 => first real entry.
    uint8_t *buf = mem + buf_ptr_u;
    uint32_t used = 0;
    uint64_t pos = 0;
    uint64_t start_cookie = (uint64_t)cookie;
    uint64_t dir_ino = 1;
    int raw_dir_fd = dirfd(dir);
    if (raw_dir_fd >= 0) {
        struct stat st;
        if (fstat(raw_dir_fd, &st) == 0) {
            dir_ino = (uint64_t)st.st_ino;
        }
    }

    if (pos >= start_cookie && used < buf_len_u) {
        int complete = 0;
        used = write_readdir_entry_with_truncation(
            buf, buf_len_u, used, 1, dir_ino, WASI_FILETYPE_DIRECTORY, ".", 1, &complete
        );
        if (!complete) {
            closedir(dir);
            *(uint32_t *)(mem + bufused_ptr_u) = used;
            return WASI_ESUCCESS;
        }
    }
    pos++;

    if (pos >= start_cookie && used < buf_len_u) {
        int complete = 0;
        used = write_readdir_entry_with_truncation(
            buf, buf_len_u, used, 2, dir_ino, WASI_FILETYPE_DIRECTORY, "..", 2, &complete
        );
        if (!complete) {
            closedir(dir);
            *(uint32_t *)(mem + bufused_ptr_u) = used;
            return WASI_ESUCCESS;
        }
    }
    pos++;

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL && used < buf_len_u) {
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
            continue;
        }
        if (pos < start_cookie) {
            pos++;
            continue;
        }

        size_t name_len = strlen(entry->d_name);
        uint8_t wasi_type = WASI_FILETYPE_UNKNOWN;
        switch (entry->d_type) {
            case DT_REG: wasi_type = WASI_FILETYPE_REGULAR_FILE; break;
            case DT_DIR: wasi_type = WASI_FILETYPE_DIRECTORY; break;
            case DT_LNK: wasi_type = WASI_FILETYPE_SYMBOLIC_LINK; break;
            case DT_CHR: wasi_type = WASI_FILETYPE_CHARACTER_DEVICE; break;
            case DT_BLK: wasi_type = WASI_FILETYPE_BLOCK_DEVICE; break;
            case DT_SOCK: wasi_type = WASI_FILETYPE_SOCKET_STREAM; break;
        }

        int complete = 0;
        used = write_readdir_entry_with_truncation(
            buf,
            buf_len_u,
            used,
            pos + 1,
            (uint64_t)entry->d_ino,
            wasi_type,
            entry->d_name,
            name_len,
            &complete
        );
        pos++;
        if (!complete) break;
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
    if (invalid_lookupflags(flags)) return trap_invalid_wasi_abi_arg();
    uint8_t *mem = ctx->memory0->base;
    uint32_t path_ptr_u = (uint32_t)path_ptr;
    uint32_t path_len_u = (uint32_t)path_len;
    uint32_t buf_ptr_u = (uint32_t)buf_ptr;
    int has_trailing_slash = path_len_u > 0 && mem[path_ptr_u + path_len_u - 1] == '/';
    if (!check_mem_range(ctx, path_ptr_u, (size_t)path_len_u)) return WASI_EFAULT;
    if (guest_bytes_contain_nul(mem, path_ptr_u, path_len_u)) return WASI_EINVAL;
    if (!guest_bytes_valid_utf8(mem, path_ptr_u, path_len_u)) return WASI_EILSEQ;
    if (!check_mem_range(ctx, buf_ptr_u, 64)) return WASI_EFAULT;

#ifndef _WIN32
    char *path_tmp = malloc((size_t)path_len_u + 1);
    if (!path_tmp) return WASI_ENOMEM;
    memcpy(path_tmp, mem + path_ptr_u, path_len_u);
    path_tmp[path_len_u] = '\0';

    char *full_path = NULL;
    int path_errno = resolve_path_with_errno(
        ctx,
        dir_fd,
        path_tmp,
        ((flags & 1) != 0),
        &full_path
    );
    free(path_tmp);
    if (path_errno != WASI_ESUCCESS) return path_errno;

    const char *stat_path = full_path;
    char *stat_path_alloc = NULL;

    if (has_trailing_slash) {
        size_t full_len = strlen(full_path);
        stat_path_alloc = malloc(full_len + 2);
        if (!stat_path_alloc) {
            free(full_path);
            return WASI_ENOMEM;
        }
        memcpy(stat_path_alloc, full_path, full_len);
        stat_path_alloc[full_len] = '/';
        stat_path_alloc[full_len + 1] = '\0';
        stat_path = stat_path_alloc;
    }

    struct stat st;
    int result;
    if (flags & 1) { // SYMLINK_FOLLOW
        result = stat(stat_path, &st);
    } else {
        result = lstat(stat_path, &st);
    }
    if (stat_path_alloc) free(stat_path_alloc);
    free(full_path);
    if (result != 0) {
        if (has_trailing_slash && errno == ENOTDIR) return WASI_ENOENT;
        return errno_to_wasi(errno);
    }

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
    if (guest_bytes_contain_nul(mem, path_ptr_u, path_len_u)) return WASI_EINVAL;
    if (!guest_bytes_valid_utf8(mem, path_ptr_u, path_len_u)) return WASI_EILSEQ;
    if (!check_mem_range(ctx, buf_ptr_u, (size_t)buf_len_u)) return WASI_EFAULT;
    if (!check_mem_range(ctx, bufused_ptr_u, 4)) return WASI_EFAULT;

#ifndef _WIN32
    char *path_tmp = malloc((size_t)path_len_u + 1);
    if (!path_tmp) return WASI_ENOMEM;
    memcpy(path_tmp, mem + path_ptr_u, path_len_u);
    path_tmp[path_len_u] = '\0';

    char *full_path = NULL;
    int path_errno = resolve_path_with_errno(ctx, dir_fd, path_tmp, 0, &full_path);
    free(path_tmp);
    if (path_errno != WASI_ESUCCESS) return path_errno;

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
    if (guest_bytes_contain_nul(mem, old_path_ptr_u, old_path_len_u) ||
        guest_bytes_contain_nul(mem, new_path_ptr_u, new_path_len_u)) {
        return WASI_EINVAL;
    }
    if (!guest_bytes_valid_utf8(mem, old_path_ptr_u, old_path_len_u) ||
        !guest_bytes_valid_utf8(mem, new_path_ptr_u, new_path_len_u)) {
        return WASI_EILSEQ;
    }

#ifndef _WIN32
    char *old_path = malloc((size_t)old_path_len_u + 1);
    if (!old_path) return WASI_ENOMEM;
    memcpy(old_path, mem + old_path_ptr_u, old_path_len_u);
    old_path[old_path_len_u] = '\0';
    if (old_path[0] == '/') {
        free(old_path);
        return WASI_EPERM;
    }

    char *new_path_tmp = malloc((size_t)new_path_len_u + 1);
    if (!new_path_tmp) {
        free(old_path);
        return WASI_ENOMEM;
    }
    memcpy(new_path_tmp, mem + new_path_ptr_u, new_path_len_u);
    new_path_tmp[new_path_len_u] = '\0';

    char *full_new_path = NULL;
    int path_errno = resolve_path_with_errno(ctx, dir_fd, new_path_tmp, 0, &full_new_path);
    free(new_path_tmp);
    if (path_errno != WASI_ESUCCESS) {
        free(old_path);
        return path_errno;
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
    if (invalid_lookupflags(old_flags)) return trap_invalid_wasi_abi_arg();
    uint8_t *mem = ctx->memory0->base;
    uint32_t old_path_ptr_u = (uint32_t)old_path_ptr;
    uint32_t old_path_len_u = (uint32_t)old_path_len;
    uint32_t new_path_ptr_u = (uint32_t)new_path_ptr;
    uint32_t new_path_len_u = (uint32_t)new_path_len;
    if (!check_mem_range(ctx, old_path_ptr_u, (size_t)old_path_len_u)) return WASI_EFAULT;
    if (!check_mem_range(ctx, new_path_ptr_u, (size_t)new_path_len_u)) return WASI_EFAULT;
    if (guest_bytes_contain_nul(mem, old_path_ptr_u, old_path_len_u) ||
        guest_bytes_contain_nul(mem, new_path_ptr_u, new_path_len_u)) {
        return WASI_EINVAL;
    }
    if (!guest_bytes_valid_utf8(mem, old_path_ptr_u, old_path_len_u) ||
        !guest_bytes_valid_utf8(mem, new_path_ptr_u, new_path_len_u)) {
        return WASI_EILSEQ;
    }

#ifndef _WIN32
    char *old_path_tmp = malloc((size_t)old_path_len_u + 1);
    if (!old_path_tmp) return WASI_ENOMEM;
    memcpy(old_path_tmp, mem + old_path_ptr_u, old_path_len_u);
    old_path_tmp[old_path_len_u] = '\0';

    char *new_path_tmp = malloc((size_t)new_path_len_u + 1);
    if (!new_path_tmp) {
        free(old_path_tmp);
        return WASI_ENOMEM;
    }
    memcpy(new_path_tmp, mem + new_path_ptr_u, new_path_len_u);
    new_path_tmp[new_path_len_u] = '\0';

    char *full_old_path = NULL;
    int old_errno = resolve_path_with_errno(ctx, old_fd, old_path_tmp, 0, &full_old_path);
    free(old_path_tmp);
    if (old_errno != WASI_ESUCCESS) {
        free(new_path_tmp);
        return old_errno;
    }

    char *full_new_path = NULL;
    int new_errno = resolve_path_with_errno(ctx, new_fd, new_path_tmp, 0, &full_new_path);
    free(new_path_tmp);
    if (new_errno != WASI_ESUCCESS) {
        free(full_old_path);
        return new_errno;
    }

    if (old_flags & 0x01) {
        free(full_old_path);
        free(full_new_path);
        return WASI_EINVAL;
    }
    int flags = 0;
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
static int unknown_fst_flags_for_set_times(int32_t fst_flags) {
    return (fst_flags & ~0x0f) != 0;
}

static int conflicting_fst_flags_for_set_times(int32_t fst_flags) {
    if ((fst_flags & 0x03) == 0x03) return 1;
    if ((fst_flags & 0x0c) == 0x0c) return 1;
    return 0;
}

static int32_t wasi_fd_filestat_set_times_impl(
    jit_context_t *ctx,
    int32_t fd, int64_t atim, int64_t mtim, int32_t fst_flags
) {
    if (unknown_fst_flags_for_set_times(fst_flags)) return trap_invalid_wasi_abi_arg();
    if (conflicting_fst_flags_for_set_times(fst_flags)) return WASI_EINVAL;
    int native_fd = -1;
    int err = get_non_stdio_native_fd(ctx, fd, &native_fd);
    if (err != WASI_ESUCCESS) return err;

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
        return errno_to_wasi(errno);
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
    if (invalid_lookupflags(flags)) return trap_invalid_wasi_abi_arg();
    if (unknown_fst_flags_for_set_times(fst_flags)) return trap_invalid_wasi_abi_arg();
    if (conflicting_fst_flags_for_set_times(fst_flags)) return WASI_EINVAL;
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint8_t *mem = ctx->memory0->base;
    uint32_t path_ptr_u = (uint32_t)path_ptr;
    uint32_t path_len_u = (uint32_t)path_len;
    int has_trailing_slash = path_len_u > 0 && mem[path_ptr_u + path_len_u - 1] == '/';
    if (!check_mem_range(ctx, path_ptr_u, (size_t)path_len_u)) return WASI_EFAULT;
    if (guest_bytes_contain_nul(mem, path_ptr_u, path_len_u)) return WASI_EINVAL;
    if (!guest_bytes_valid_utf8(mem, path_ptr_u, path_len_u)) return WASI_EILSEQ;

#ifndef _WIN32
    char *path_tmp = malloc((size_t)path_len_u + 1);
    if (!path_tmp) return WASI_ENOMEM;
    memcpy(path_tmp, mem + path_ptr_u, path_len_u);
    path_tmp[path_len_u] = '\0';

    char *full_path = NULL;
    int path_errno = resolve_path_with_errno(
        ctx,
        dir_fd,
        path_tmp,
        ((flags & 1) != 0),
        &full_path
    );
    free(path_tmp);
    if (path_errno != WASI_ESUCCESS) return path_errno;

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

    const char *stat_path = full_path;
    char *stat_path_alloc = NULL;
    int at_flags = (flags & 1) ? 0 : AT_SYMLINK_NOFOLLOW;

    if (has_trailing_slash) {
        // Keep parity with the interpreter path: trailing slash targets must be directories.
        struct stat st_check;
        if (fstatat(AT_FDCWD, full_path, &st_check, at_flags) != 0) {
            int err = errno_to_wasi(errno);
            free(full_path);
            if (err == WASI_ENOTDIR) return WASI_ENOENT;
            return err;
        }
        if (!S_ISDIR(st_check.st_mode)) {
            free(full_path);
            return WASI_ENOENT;
        }
    }
    if (has_trailing_slash) {
        size_t full_len = strlen(full_path);
        stat_path_alloc = malloc(full_len + 2);
        if (!stat_path_alloc) {
            free(full_path);
            return WASI_ENOMEM;
        }
        memcpy(stat_path_alloc, full_path, full_len);
        stat_path_alloc[full_len] = '/';
        stat_path_alloc[full_len + 1] = '\0';
        stat_path = stat_path_alloc;
    }

    int result = utimensat(AT_FDCWD, stat_path, times, at_flags);
    if (stat_path_alloc) free(stat_path_alloc);
    free(full_path);
    if (result != 0) {
        if (has_trailing_slash && errno == ENOTDIR) return WASI_ENOENT;
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
    if (advice < 0 || advice > 5) return trap_invalid_wasi_abi_arg();
    int native_fd = -1;
    int err = get_regular_file_native_fd(ctx, fd, &native_fd);
    if (err != WASI_ESUCCESS) return err;
    (void)native_fd;
    // Advisory only, always succeed
    return WASI_ESUCCESS;
}

// fd_fdstat_set_rights: irrevocably reduce descriptor rights
static int32_t wasi_fd_fdstat_set_rights_impl(
    jit_context_t *ctx,
    int32_t fd, int64_t rights_base, int64_t rights_inheriting
) {
    if (!ctx) return WASI_EBADF;
    if (is_stdio_fd(ctx, fd)) return WASI_EBADF;
    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;
    if (!ctx->fd_rights_base || !ctx->fd_rights_inheriting ||
        fd < 0 || fd >= ctx->fd_table_size) return WASI_EBADF;
    uint64_t new_base = (uint64_t)rights_base;
    uint64_t new_inheriting = (uint64_t)rights_inheriting;
    if ((new_base & ~WASI_RIGHTS_ALL_VALID) != 0 ||
        (new_inheriting & ~WASI_RIGHTS_ALL_VALID) != 0) {
        return WASI_EINVAL;
    }
    if ((new_base & ctx->fd_rights_base[fd]) != new_base ||
        (new_inheriting & ctx->fd_rights_inheriting[fd]) != new_inheriting) {
        return WASI_ENOTCAPABLE;
    }
    ctx->fd_rights_base[fd] = new_base;
    ctx->fd_rights_inheriting[fd] = new_inheriting;
    return WASI_ESUCCESS;
}

// fd_allocate: Allocate space for a file
static int32_t wasi_fd_allocate_impl(
    jit_context_t *ctx,
    int32_t fd, int64_t offset, int64_t len
) {
    (void)offset;
    (void)len;
    int native_fd = -1;
    int err = get_regular_file_native_fd(ctx, fd, &native_fd);
    if (err != WASI_ESUCCESS) return err;
    (void)native_fd;
    return WASI_ENOTSUP;
}

static void renumber_preopen_entries(jit_context_t *ctx, int from_fd, int to_fd) {
    if (!ctx || !ctx->preopen_fds) return;
    int moved_idx = -1;
    for (int i = 0; i < ctx->preopen_count; i++) {
        if (ctx->preopen_fds[i] == from_fd) {
            moved_idx = i;
        } else if (ctx->preopen_fds[i] == to_fd) {
            ctx->preopen_fds[i] = -1;
        }
    }
    if (moved_idx >= 0) {
        ctx->preopen_fds[moved_idx] = to_fd;
    }
}

static void close_replaced_native_fd(int native_fd) {
    if (native_fd <= 2) return;
#ifdef _WIN32
    _close(native_fd);
#else
    close(native_fd);
#endif
}

// fd_renumber: Renumber a file descriptor
static int32_t wasi_fd_renumber_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t to_fd
) {
    if (!ctx || !ctx->fd_table) return WASI_EBADF;

    int from_valid = is_valid_wasi_descriptor(ctx, fd);
    int to_valid = is_valid_wasi_descriptor(ctx, to_fd);
    if (!from_valid || !to_valid) return WASI_EBADF;
    if (fd == to_fd) return WASI_ESUCCESS;

    int native_fd = get_native_fd(ctx, fd);
    int native_to_fd = get_native_fd(ctx, to_fd);
    if (native_fd < 0 || native_to_fd < 0) return WASI_EBADF;
    int same_native = (native_fd == native_to_fd);

    int from_stdio_slot = stdio_slot_for_fd(ctx, fd);
    int to_stdio_slot = stdio_slot_for_fd(ctx, to_fd);

    renumber_preopen_entries(ctx, fd, to_fd);

    if (!same_native) {
        close_replaced_native_fd(native_to_fd);
    }

    if (to_stdio_slot >= 0) {
        clear_stdio_slot(ctx, to_stdio_slot);
    }

    if (ctx->fd_host_paths && ctx->fd_is_dir) {
        clear_fd_metadata(ctx, to_fd);
    }

    ctx->fd_table[to_fd] = native_fd;
    ctx->fd_table[fd] = -1;

    if (from_stdio_slot >= 0) {
        move_stdio_slot_to_fd(ctx, from_stdio_slot, to_fd);
        if (ctx->fd_host_paths && ctx->fd_is_dir) {
            clear_fd_metadata(ctx, to_fd);
            clear_fd_metadata(ctx, fd);
        }
    } else {
        if (ctx->fd_host_paths && ctx->fd_is_dir) {
            ctx->fd_host_paths[to_fd] = ctx->fd_host_paths[fd];
            ctx->fd_is_dir[to_fd] = ctx->fd_is_dir[fd];
            ctx->fd_host_paths[fd] = NULL;
            ctx->fd_is_dir[fd] = 0;
        }
        if (ctx->fd_rights_base && ctx->fd_rights_inheriting) {
            ctx->fd_rights_base[to_fd] = ctx->fd_rights_base[fd];
            ctx->fd_rights_inheriting[to_fd] = ctx->fd_rights_inheriting[fd];
            ctx->fd_rights_base[fd] = 0;
            ctx->fd_rights_inheriting[fd] = 0;
        }
    }

    if (ctx->fd_host_paths && ctx->fd_is_dir) {
        clear_fd_metadata(ctx, fd);
    }

    return WASI_ESUCCESS;
}

// fd_fdstat_set_flags: Set file descriptor flags
static int32_t wasi_fd_fdstat_set_flags_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t flags
) {
    if ((flags & ~0x1f) != 0) {
        return trap_invalid_wasi_abi_arg();
    }
    if (is_stdio_fd(ctx, fd)) return WASI_EBADF;
    if (is_preopen_fd(ctx, fd) || get_open_dir_path(ctx, fd)) return WASI_EBADF;

    int native_fd = get_native_fd(ctx, fd);
    if (native_fd < 0) return WASI_EBADF;
    // Match wasmtime behavior:
    // - unknown fdflags bits are rejected before descriptor lookup
    // - DSYNC/RSYNC/SYNC are rejected with EINVAL only for valid file descriptors
    if ((flags & 0x02) != 0 || (flags & 0x08) != 0 || (flags & 0x10) != 0) {
        return WASI_EINVAL;
    }

#ifndef _WIN32
    int native_flags = fcntl(native_fd, F_GETFL);
    if (native_flags < 0) return errno_to_wasi(errno);

    if (flags & 0x01) native_flags |= O_APPEND;
    else native_flags &= ~O_APPEND;
#ifdef O_NONBLOCK
    if (flags & 0x04) native_flags |= O_NONBLOCK;
    else native_flags &= ~O_NONBLOCK;
#endif

    if (fcntl(native_fd, F_SETFL, native_flags) < 0) return errno_to_wasi(errno);
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

// sock_accept: Accept a connection on a socket
// fd: The listening socket
// flags: Desired flags for the accepted socket (currently unused)
// result_fd_ptr: Where to store the new socket fd
static int32_t wasi_sock_accept_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t flags, int32_t result_fd_ptr
) {
    if (!ctx || !ctx->memory0 || !ctx->memory0->base) return WASI_EBADF;
    uint32_t result_fd_ptr_u = (uint32_t)result_fd_ptr;
    if (!check_mem_range(ctx, result_fd_ptr_u, 4)) return WASI_EFAULT;
    if (invalid_sock_accept_fdflags(flags)) return trap_invalid_wasi_abi_arg();

    if (!is_valid_wasi_descriptor(ctx, fd)) return WASI_EBADF;
    return WASI_ENOTSOCK;
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
    if (!check_mem_range(ctx, ro_flags_ptr_u, 2)) return WASI_EFAULT;
    if (invalid_sock_recv_riflags(ri_flags)) return trap_invalid_wasi_abi_arg();

    (void)ri_data_u;
    (void)ri_data_len_u;
    (void)ri_flags;
    (void)ro_datalen_ptr_u;
    (void)ro_flags_ptr_u;
    if (!is_valid_wasi_descriptor(ctx, fd)) return WASI_EBADF;
    return WASI_ENOTSOCK;
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

    (void)si_data_u;
    (void)si_data_len_u;
    (void)si_flags;
    (void)so_datalen_ptr_u;
    if (!is_valid_wasi_descriptor(ctx, fd)) return WASI_EBADF;
    return WASI_ENOTSOCK;
}

// sock_shutdown: Shut down a socket
// fd: Socket to shut down
// how: 0=RD, 1=WR, 2=RDWR
static int32_t wasi_sock_shutdown_impl(
    jit_context_t *ctx,
    int32_t fd, int32_t how
) {
    if (!ctx) return WASI_EBADF;
    if (invalid_sock_shutdown_sdflags(how)) return trap_invalid_wasi_abi_arg();
    if (!is_valid_wasi_descriptor(ctx, fd)) return WASI_EBADF;
    return WASI_ENOTSOCK;
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
    ctx->stdin_fd = 0;
    ctx->stdout_fd = 1;
    ctx->stderr_fd = 2;
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
        set_fd_rights(
            ctx,
            0,
            WASI_RIGHT_FD_READ | WASI_RIGHT_POLL_FD_READWRITE,
            0
        );
        set_fd_rights(
            ctx,
            1,
            WASI_RIGHT_FD_WRITE | WASI_RIGHT_POLL_FD_READWRITE,
            0
        );
        set_fd_rights(
            ctx,
            2,
            WASI_RIGHT_FD_WRITE | WASI_RIGHT_POLL_FD_READWRITE,
            0
        );
    }
    ctx->fd_next = 3 + preopen_count;

    if (preopen_count > 0) {
        ctx->preopen_paths = malloc(preopen_count * sizeof(char*));
        ctx->preopen_guest_paths = malloc(preopen_count * sizeof(char*));
        ctx->preopen_fds = malloc(preopen_count * sizeof(int));
        if (ctx->preopen_paths && ctx->preopen_guest_paths && ctx->preopen_fds) {
            for (int i = 0; i < preopen_count; i++) {
                ctx->preopen_paths[i] = NULL;
                ctx->preopen_guest_paths[i] = NULL;
                ctx->preopen_fds[i] = ctx->preopen_base_fd + i;
            }
        }
    }
}

// Quiet version: redirects stdout/stderr to /dev/null for testing
MOONBIT_FFI_EXPORT void wasmoon_jit_init_wasi_fds_quiet(int64_t ctx_ptr, int preopen_count) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;

    ctx->preopen_base_fd = 3;
    ctx->preopen_count = preopen_count;
    ctx->fd_table_size = 64;
    ctx->stdin_fd = 0;
    ctx->stdout_fd = 1;
    ctx->stderr_fd = 2;
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
        set_fd_rights(
            ctx,
            0,
            WASI_RIGHT_FD_READ | WASI_RIGHT_POLL_FD_READWRITE,
            0
        );
        set_fd_rights(
            ctx,
            1,
            WASI_RIGHT_FD_WRITE | WASI_RIGHT_POLL_FD_READWRITE,
            0
        );
        set_fd_rights(
            ctx,
            2,
            WASI_RIGHT_FD_WRITE | WASI_RIGHT_POLL_FD_READWRITE,
            0
        );
    }
    ctx->fd_next = 3 + preopen_count;

    if (preopen_count > 0) {
        ctx->preopen_paths = malloc(preopen_count * sizeof(char*));
        ctx->preopen_guest_paths = malloc(preopen_count * sizeof(char*));
        ctx->preopen_fds = malloc(preopen_count * sizeof(int));
        if (ctx->preopen_paths && ctx->preopen_guest_paths && ctx->preopen_fds) {
            for (int i = 0; i < preopen_count; i++) {
                ctx->preopen_paths[i] = NULL;
                ctx->preopen_guest_paths[i] = NULL;
                ctx->preopen_fds[i] = ctx->preopen_base_fd + i;
            }
        }
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
    if (closure) moonbit_incref(closure);
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
    if (!ctx || !ctx->preopen_paths || !ctx->preopen_fds || idx < 0 || idx >= ctx->preopen_count) return;

    ctx->preopen_paths[idx] = strdup(host_path);
    ctx->preopen_guest_paths[idx] = strdup(guest_path);
#ifndef _WIN32
    if (ctx->fd_table) {
        int wasi_fd = ctx->preopen_fds[idx];
        if (wasi_fd >= 0 && wasi_fd < ctx->fd_table_size) {
            int native_fd = open(host_path, O_RDONLY | O_DIRECTORY);
            if (native_fd >= 0) {
                ctx->fd_table[wasi_fd] = native_fd;
                set_fd_metadata(ctx, wasi_fd, strdup(host_path), 1);
                set_fd_rights(
                    ctx,
                    wasi_fd,
                    preopen_directory_base_rights(),
                    preopen_directory_inheriting_rights()
                );
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

    // Close all open native descriptors while preserving process stdio.
    if (ctx->fd_table) {
        for (int i = 0; i < ctx->fd_table_size; i++) {
            if (ctx->fd_table[i] >= 0) {
                int native_fd = ctx->fd_table[i];
                if (native_fd <= 2) continue;
                int seen = 0;
                for (int j = 0; j < i; j++) {
                    if (ctx->fd_table[j] == native_fd) {
                        seen = 1;
                        break;
                    }
                }
                if (seen) continue;
#ifndef _WIN32
                close(native_fd);
#else
                _close(native_fd);
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
        if (ctx->fd_rights_base) {
            free(ctx->fd_rights_base);
            ctx->fd_rights_base = NULL;
        }
        if (ctx->fd_rights_inheriting) {
            free(ctx->fd_rights_inheriting);
            ctx->fd_rights_inheriting = NULL;
        }
        free(ctx->fd_table);
        ctx->fd_table = NULL;
        ctx->fd_table_size = 0;
        ctx->fd_next = 0;
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
    if (ctx->preopen_fds) {
        free(ctx->preopen_fds);
        ctx->preopen_fds = NULL;
    }
    ctx->preopen_count = 0;
    ctx->preopen_base_fd = 0;
    ctx->stdin_fd = -1;
    ctx->stdout_fd = -1;
    ctx->stderr_fd = -1;

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
