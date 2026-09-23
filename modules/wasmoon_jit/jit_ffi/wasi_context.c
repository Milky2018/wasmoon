// Native JIT compatibility state. Guest WASI calls use the shared hostcall bridge.
#include "jit_internal.h"
#include <errno.h>
#ifndef _WIN32
#include <fcntl.h>
#else
#include <io.h>
#endif

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

static uint64_t readonly_directory_base_rights(void) {
    return WASI_RIGHT_PATH_OPEN | WASI_RIGHT_FD_READDIR | WASI_RIGHT_PATH_READLINK |
        WASI_RIGHT_PATH_FILESTAT_GET | WASI_RIGHT_FD_FILESTAT_GET;
}

static uint64_t readonly_directory_inheriting_rights(void) {
    return readonly_directory_base_rights() | WASI_RIGHT_FD_READ | WASI_RIGHT_FD_SEEK |
        WASI_RIGHT_FD_TELL | WASI_RIGHT_FD_ADVISE | WASI_RIGHT_FD_FDSTAT_SET_FLAGS |
        WASI_RIGHT_POLL_FD_READWRITE;
}

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
        WASI_RIGHT_PATH_FILESTAT_SET_SIZE |
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

// ============ Context Initialization ============

static void init_wasi_fds(int64_t ctx_ptr, int preopen_count, int quiet) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx) return;

    wasmoon_jit_free_wasi_fds(ctx_ptr);
    if (preopen_count < 0 || preopen_count > INT32_MAX - 3) return;
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
        int devnull = quiet ? open("/dev/null", O_WRONLY) : -1;
        ctx->fd_table[1] = devnull >= 0 ? devnull : 1;
        ctx->fd_table[2] = devnull >= 0 ? devnull : 2;
#else
        (void)quiet;
        ctx->fd_table[1] = 1;
        ctx->fd_table[2] = 2;
#endif
    }
    if (!ctx->fd_table || !ensure_fd_metadata_arrays(ctx)) {
        wasmoon_jit_free_wasi_fds(ctx_ptr);
        return;
    }
    {
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
        ctx->preopen_paths = calloc((size_t)preopen_count, sizeof(char*));
        ctx->preopen_guest_paths = calloc((size_t)preopen_count, sizeof(char*));
        ctx->preopen_fds = malloc(preopen_count * sizeof(int));
        if (ctx->preopen_paths && ctx->preopen_guest_paths && ctx->preopen_fds) {
            for (int i = 0; i < preopen_count; i++) {
                ctx->preopen_paths[i] = NULL;
                ctx->preopen_guest_paths[i] = NULL;
                ctx->preopen_fds[i] = ctx->preopen_base_fd + i;
            }
        } else {
            wasmoon_jit_free_wasi_fds(ctx_ptr);
        }
    }
}

MOONBIT_FFI_EXPORT void wasmoon_jit_init_wasi_fds(int64_t ctx_ptr, int preopen_count) {
    init_wasi_fds(ctx_ptr, preopen_count, 0);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_init_wasi_fds_quiet(int64_t ctx_ptr, int preopen_count) {
    init_wasi_fds(ctx_ptr, preopen_count, 1);
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
    if (!ctx) {
        if (closure) moonbit_decref(closure);
        return;
    }
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

static void add_preopen_with_mode(int64_t ctx_ptr, int idx, const char *host_path, const char *guest_path, int read_only) {
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    if (!ctx || !ctx->preopen_paths || !ctx->preopen_guest_paths || !ctx->preopen_fds || idx < 0 || idx >= ctx->preopen_count) return;

    free(ctx->preopen_paths[idx]);
    free(ctx->preopen_guest_paths[idx]);
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
                    read_only ? readonly_directory_base_rights() : preopen_directory_base_rights(),
                    read_only ? readonly_directory_inheriting_rights() : preopen_directory_inheriting_rights()
                );
            }
        }
    }
#endif
}

MOONBIT_FFI_EXPORT void wasmoon_jit_add_preopen(int64_t ctx_ptr, int idx, const char *host_path, const char *guest_path) {
    add_preopen_with_mode(ctx_ptr, idx, host_path, guest_path, 0);
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

    for (int i = 0; i < ctx->preopen_count; i++) {
        if (ctx->preopen_paths) free(ctx->preopen_paths[i]);
        if (ctx->preopen_guest_paths) free(ctx->preopen_guest_paths[i]);
    }
    free(ctx->preopen_paths);
    free(ctx->preopen_guest_paths);
    ctx->preopen_paths = NULL;
    ctx->preopen_guest_paths = NULL;
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

extern int64_t wasmoon_jit_context_ptr(void *jit_context);

#define MANAGED_CTX(jit_context) wasmoon_jit_context_ptr(jit_context)

MOONBIT_FFI_EXPORT void wasmoon_jit_init_wasi_fds_managed(
    void *jit_context, int preopen_count
) {
    wasmoon_jit_init_wasi_fds(MANAGED_CTX(jit_context), preopen_count);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_init_wasi_fds_quiet_managed(
    void *jit_context, int preopen_count
) {
    wasmoon_jit_init_wasi_fds_quiet(
        MANAGED_CTX(jit_context), preopen_count
    );
}

MOONBIT_FFI_EXPORT void wasmoon_jit_add_preopen_managed(
    void *jit_context,
    int idx,
    const char *host_path,
    const char *guest_path,
    int read_only
) {
    add_preopen_with_mode(
        MANAGED_CTX(jit_context), idx, host_path, guest_path, read_only
    );
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_stdout_capture_managed(
    void *jit_context, int enabled
) {
    wasmoon_jit_set_wasi_stdout_capture(MANAGED_CTX(jit_context), enabled);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_stderr_capture_managed(
    void *jit_context, int enabled
) {
    wasmoon_jit_set_wasi_stderr_capture(MANAGED_CTX(jit_context), enabled);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_stdin_buffer_managed(
    void *jit_context, moonbit_bytes_t data, int len
) {
    wasmoon_jit_set_wasi_stdin_buffer(
        MANAGED_CTX(jit_context), data, len
    );
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_stdin_callback_managed(
    void *jit_context,
    wasi_stdin_callback_fn callback,
    void *closure
) {
    wasmoon_jit_set_wasi_stdin_callback(
        MANAGED_CTX(jit_context), callback, closure
    );
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_wasi_stdin_buffer_managed(
    void *jit_context
) {
    wasmoon_jit_clear_wasi_stdin_buffer(MANAGED_CTX(jit_context));
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_wasi_stdin_callback_managed(
    void *jit_context
) {
    wasmoon_jit_clear_wasi_stdin_callback(MANAGED_CTX(jit_context));
}

MOONBIT_FFI_EXPORT moonbit_bytes_t wasmoon_jit_take_wasi_stdout_managed(
    void *jit_context
) {
    return wasmoon_jit_take_wasi_stdout(MANAGED_CTX(jit_context));
}

MOONBIT_FFI_EXPORT moonbit_bytes_t wasmoon_jit_take_wasi_stderr_managed(
    void *jit_context
) {
    return wasmoon_jit_take_wasi_stderr(MANAGED_CTX(jit_context));
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_args_managed(
    void *jit_context, int argc
) {
    wasmoon_jit_set_wasi_args(MANAGED_CTX(jit_context), argc);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_arg_managed(
    void *jit_context, int idx, const char *arg
) {
    wasmoon_jit_set_wasi_arg(MANAGED_CTX(jit_context), idx, arg);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_envs_managed(
    void *jit_context, int envc
) {
    wasmoon_jit_set_wasi_envs(MANAGED_CTX(jit_context), envc);
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_env_managed(
    void *jit_context, int idx, const char *env
) {
    wasmoon_jit_set_wasi_env(MANAGED_CTX(jit_context), idx, env);
}

MOONBIT_FFI_EXPORT int wasmoon_jit_get_wasi_exit_code_managed(
    void *jit_context
) {
    return wasmoon_jit_get_wasi_exit_code(MANAGED_CTX(jit_context));
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_wasi_exit_managed(
    void *jit_context
) {
    wasmoon_jit_clear_wasi_exit(MANAGED_CTX(jit_context));
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_exit_code_managed(void *jit_context, int code) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)MANAGED_CTX(jit_context);
    ctx->wasi_exited = 1;
    ctx->wasi_exit_code = code;
}

#undef MANAGED_CTX
