#include "../jit_internal.h"

static int run_exception_failure(jit_trap_activation_t *activation, int mode) {
    if (sigsetjmp(activation->jmp_buf, 1) == 0) {
        if (mode == 1) {
            exception_try_begin_impl(activation->context, 1);
            exception_try_end_impl(activation->context, 1);
        } else if (mode == 3) {
            exception_capture_payload(activation->context, 0, NULL, 0);
        } else if (mode == 4) {
            ctx_execution(activation->context)->exception_tag = 0;
            exception_capture_current(activation->context);
        } else {
            int64_t locals[2] = {37, 0};
            exception_spill_locals_impl(activation->context, locals, 1);
        }
    }
    return (int)activation->code;
}

MOONBIT_FFI_EXPORT int wasmoon_test_native_failure_recovery(void) {
    jit_context_t *ctx = alloc_context_internal(0);
    if (!ctx) return 0;
    int passed = 1;
    for (int mode = 1; mode <= 4; ++mode) {
        if (mode >= 3) {
            exception_arena_release(ctx_runtime(ctx)->exception_arena);
            ctx_runtime(ctx)->exception_arena = NULL;
        }
        jit_trap_activation_t activation;
        jit_trap_activation_init(&activation, ctx);
        if (!jit_trap_activation_push(&activation)) { passed = 0; break; }
        wasmoon_native_fail_allocation_for_tests(1);
        int code = run_exception_failure(&activation, mode);
        wasmoon_native_fail_allocation_for_tests(0);
        if (code != 9) passed = 0;
        jit_trap_activation_pop(&activation);
        // The same context must support the operation after denial.
        jit_trap_activation_init(&activation, ctx);
        if (!jit_trap_activation_push(&activation)) { passed = 0; break; }
        if (run_exception_failure(&activation, mode) != 0) passed = 0;
        jit_trap_activation_pop(&activation);
    }
    // Standalone state creation is also fallible, outside a setjmp boundary.
    int64_t root = 37;
    wasmoon_native_fail_allocation_for_tests(1);
    if (ctx_gc_set_root_scratch_internal(ctx, &root, 1) != 0) passed = 0;
    wasmoon_native_fail_allocation_for_tests(0);
    if (!ctx_gc_set_root_scratch_internal(ctx, &root, 1)) passed = 0;
    jit_execution_state_t *previous = ctx_runtime(ctx)->execution;
    // Failure while copying entry roots must restore the previous execution.
    jit_trap_activation_t entry;
    jit_trap_activation_init(&entry, ctx);
    wasmoon_native_fail_allocation_for_tests(1);
    if (jit_trap_activation_push(&entry)) {
        passed = 0;
        jit_trap_activation_pop(&entry);
    }
    wasmoon_native_fail_allocation_for_tests(0);
    if (ctx_runtime(ctx)->execution != previous ||
        previous->gc_root_scratch_len != 1 || previous->gc_root_scratch[0] != root ||
        get_current_jit_context() != NULL) passed = 0;
    jit_trap_activation_init(&entry, ctx);
    if (!jit_trap_activation_push(&entry)) passed = 0;
    else jit_trap_activation_pop(&entry);
    free_context_internal(ctx);
    return passed;
}
