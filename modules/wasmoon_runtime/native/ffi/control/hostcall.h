#ifndef WASMOON_HOSTCALL_H
#define WASMOON_HOSTCALL_H

#include "../context/jit_context.h"

int wasmoon_jit_cancellation_requested(jit_context_t *ctx);
jit_invocation_controls_t *jit_execution_controls(jit_context_t *ctx);

int wasmoon_jit_call_trampoline_caught(int64_t trampoline_ptr, int64_t ctx_ptr,
    int64_t func_ptr, int64_t *values, int values_len, int64_t *exception);
int wasmoon_jit_call_trampoline_captured(int64_t trampoline_ptr, int64_t ctx_ptr,
    int64_t func_ptr, int64_t *values, int values_len, int64_t *exception, void **roots);

MOONBIT_FFI_EXPORT int wasmoon_jit_call_trampoline(
    int64_t trampoline, int64_t context, int64_t function, int64_t *values, int count);
MOONBIT_FFI_EXPORT int32_t WASMOON_GUEST_ABI wasmoon_jit_hostcall(
    jit_context_t *ctx, int32_t index, int64_t values, int32_t arguments, int32_t results);
MOONBIT_FFI_EXPORT void wasmoon_jit_set_cancellation_callback(
    int64_t ctx, int32_t (*callback)(void *), void *closure);
MOONBIT_FFI_EXPORT void wasmoon_jit_clear_cancellation_callback(int64_t ctx);

#endif
