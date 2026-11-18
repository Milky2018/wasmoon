// Copyright 2025
#include "../control/trap.h"
#include "../control/exception.h"
#include "../control/hostcall.h"
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <malloc.h>
#elif defined(__APPLE__)
#include <pthread.h>
#endif

// ============ Trampoline-based Call ============

typedef int (*entry_trampoline_fn)(jit_context_t *vmctx, int64_t *values_vec, void *func_ptr);

#if defined(__x86_64__) || defined(_M_X64)
// ABI-safe wrapper implemented in `trampoline_call_x86_64.S`.
// JIT-generated entry trampolines intentionally use reserved callee-saved
// registers as pinned VMContext/cache registers and may clobber them.
// Calling them directly from C would violate SysV guarantees and corrupt the
// caller's state.
extern int wasmoon_call_entry_trampoline(
    void *trampoline_ptr,
    void *vmctx,
    void *values_vec,
    void *func_ptr
);
#endif

jit_context_t *get_current_jit_context(void) {
    return get_current_jit_context_fast();
}

// Keep mutable activation storage in the caller of setjmp. Its contents remain
// defined after longjmp, unlike modified automatic locals in this function.
static int invoke_trampoline_caught(
    jit_trap_activation_t *activation,
    int64_t trampoline_ptr,
    jit_context_t *ctx,
    int64_t func_ptr,
    int64_t *values_vec,
    int64_t *exception,
    void **exception_roots
) {
#ifdef __APPLE__
    // Darwin siglongjmp with savemask=1 changes every thread's mask.
    // Capture the recovery stack before entering guest code, including fibers.
    pthread_sigmask(SIG_SETMASK, NULL, &activation->signal_mask);
#if defined(__aarch64__)
    __asm__ volatile("mov %0, sp" : "=r"(activation->signal_landing_sp));
#elif defined(__x86_64__)
    __asm__ volatile("movq %%rsp, %0" : "=r"(activation->signal_landing_sp));
#endif
    if (sigsetjmp(activation->jmp_buf, 0) != 0) {
        pthread_sigmask(SIG_SETMASK, &activation->signal_mask, NULL);
#else
    if (sigsetjmp(activation->jmp_buf, 1) != 0) {
#endif
#ifdef _WIN32
        if ((DWORD)activation->signal == EXCEPTION_STACK_OVERFLOW) {
            // Guard restoration may protect abandoned guest frames. Snapshot
            // their chain first, while the recorded readable range is valid.
            jit_trap_activation_finalize(activation);
            if (!_resetstkoflw()) abort();
        }
#endif
        int trap_code = (int)activation->code;
        if (exception && trap_code == 12) {
            *exception = exception_capture_current(ctx);
            GcHeap *heap = ctx_gc_heap(ctx);
            if (exception_roots && heap) {
                int64_t *roots = NULL;
                if (!gc_heap_register_parked_roots(heap, 1, exception_roots, &roots)) {
                    *exception = 0;
                    activation->code = trap_code = 9;
                } else {
                    roots[0] = *exception;
                }
            }
        }
        jit_trap_activation_finalize(activation);
        jit_trap_activation_publish(activation);
        return trap_code;
    }

    int result;
#if defined(__x86_64__) || defined(_M_X64)
    result = wasmoon_call_entry_trampoline(
        (void *)trampoline_ptr,
        ctx,
        values_vec,
        (void *)func_ptr
    );
#else
    entry_trampoline_fn trampoline = (entry_trampoline_fn)trampoline_ptr;
    result = trampoline(ctx, values_vec, (void *)func_ptr);
#endif

    int trap_code = (int)activation->code;
    jit_trap_activation_finalize(activation);
    jit_trap_activation_publish(activation);

    if (trap_code != 0) {
        return trap_code;
    }

    return result;
}

static int call_trampoline_with_activation(
    int64_t trampoline_ptr,
    int64_t ctx_ptr,
    int64_t func_ptr,
    int64_t *values_vec,
    int values_len,
    int64_t *exception,
    void **exception_roots,
    int inherit_controls
) {
    (void)values_len;

    if (!trampoline_ptr || !ctx_ptr || !func_ptr) return -1;

    if (!install_trap_handler()) return 9;
    jit_context_t *ctx = (jit_context_t *)ctx_ptr;
    ctx_refresh_memory0_fast_fields(ctx);
    jit_trap_activation_t activation;
    jit_trap_activation_init(&activation, ctx);
    // Guest continuations retain their defining module, but scheduling and
    // cancellation belong to the invocation that is currently resuming them.
    activation.inherit_controls = inherit_controls;
    if (!jit_trap_activation_push(&activation)) {
        activation.code = 9;
        jit_trap_activation_publish(&activation);
        return 9;
    }

    int result = invoke_trampoline_caught(
        &activation, trampoline_ptr, ctx, func_ptr, values_vec, exception,
        exception_roots);
    jit_trap_activation_pop(&activation);
    return result;
}

int wasmoon_jit_call_trampoline_caught(
    int64_t trampoline_ptr, int64_t ctx_ptr, int64_t func_ptr,
    int64_t *values_vec, int values_len, int64_t *exception
) {
    return call_trampoline_with_activation(trampoline_ptr, ctx_ptr, func_ptr,
        values_vec, values_len, exception, NULL, exception != NULL);
}

// A host entry owns its controls and its completed exception delivery. Guest
// continuation catchers above still inherit the enclosing guest invocation.
int wasmoon_jit_call_trampoline_captured(
    int64_t trampoline_ptr, int64_t ctx_ptr, int64_t func_ptr,
    int64_t *values_vec, int values_len, int64_t *exception, void **roots
) {
    return call_trampoline_with_activation(trampoline_ptr, ctx_ptr, func_ptr,
        values_vec, values_len, exception, roots, 0);
}

MOONBIT_FFI_EXPORT int wasmoon_jit_call_trampoline(int64_t trampoline_ptr,
    int64_t ctx_ptr, int64_t func_ptr, int64_t *values_vec, int values_len) {
    return wasmoon_jit_call_trampoline_caught(trampoline_ptr, ctx_ptr,
        func_ptr, values_vec, values_len, NULL);
}

MOONBIT_FFI_EXPORT int wasmoon_jit_call_trampoline_managed(
    void *jit_context,
    int64_t trampoline_ptr,
    int64_t func_ptr,
    int64_t *values_vec,
    int values_len
) {
    if (!jit_context) return -1;
    int64_t ctx_ptr = wasmoon_jit_context_ptr(jit_context);
    return wasmoon_jit_call_trampoline(trampoline_ptr, ctx_ptr, func_ptr, values_vec, values_len);
}

// Generate a leaf context-binding entry. No guest argument, result-area register,
// return address or stack slot is modified except the explicit VMContext argument.
MOONBIT_FFI_EXPORT int wasmoon_jit_write_bound_entry_code(
    void *managed_context, int64_t target, uint8_t *output
) {
    uint64_t context = (uint64_t)wasmoon_jit_context_ptr(managed_context);
    if (!context || !target) return 0;
#if defined(__aarch64__) || defined(_M_ARM64)
    uint64_t values[2] = {context, (uint64_t)target};
    unsigned registers[2] = {0, 16};
    int offset = 0;
    for (int value = 0; value < 2; value++) {
        for (unsigned half = 0; half < 4; half++) {
            uint32_t instruction = (half == 0 ? 0xd2800000u : 0xf2800000u)
                | (half << 21)
                | ((uint32_t)((values[value] >> (half * 16)) & 0xffffu) << 5)
                | registers[value];
            memcpy(output + offset, &instruction, 4);
            offset += 4;
        }
    }
    uint32_t branch = 0xd61f0200u; // br x16
    memcpy(output + offset, &branch, 4);
    return offset + 4;
#elif defined(__x86_64__) || defined(_M_X64)
    output[0] = 0x48; output[1] = 0xbf; // movabs rdi, context
    memcpy(output + 2, &context, 8);
    output[10] = 0x49; output[11] = 0xbb; // movabs r11, target
    memcpy(output + 12, &target, 8);
    output[20] = 0x41; output[21] = 0xff; output[22] = 0xe3; // jmp r11
    return 23;
#else
    return 0;
#endif
}
