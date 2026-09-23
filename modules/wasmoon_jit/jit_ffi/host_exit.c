// Exit status transport for shared MoonBit WASI hostcalls.
#include "jit_internal.h"

extern int64_t wasmoon_jit_context_ptr(void *jit_context);

MOONBIT_FFI_EXPORT int wasmoon_jit_get_wasi_exit_code_managed(void *jit_context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(jit_context);
    if (!ctx || !ctx->wasi_exited) return -1;
    return ctx->wasi_exit_code;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_clear_wasi_exit_managed(void *jit_context) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(jit_context);
    if (!ctx) return;
    ctx->wasi_exited = 0;
    ctx->wasi_exit_code = 0;
}

MOONBIT_FFI_EXPORT void wasmoon_jit_set_wasi_exit_code_managed(void *jit_context, int code) {
    jit_context_t *ctx = (jit_context_t *)(uintptr_t)wasmoon_jit_context_ptr(jit_context);
    ctx->wasi_exited = 1;
    ctx->wasi_exit_code = code;
}
