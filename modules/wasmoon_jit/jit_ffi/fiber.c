#include "jit_internal.h"

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#if defined(WASMOON_ADDRESS_SANITIZER)
#include <sanitizer/common_interface_defs.h>
#define WASMOON_NO_ADDRESS_SANITIZE __attribute__((no_sanitize("address")))
#else
#define WASMOON_NO_ADDRESS_SANITIZE
#endif

typedef int64_t (*native_fiber_entry_fn)(void *closure);

static WASMOON_NO_FUNCTION_SANITIZE int64_t call_native_fiber_entry(
    native_fiber_entry_fn entry,
    void *closure
) {
    return entry(closure);
}

typedef enum {
    NATIVE_FIBER_READY = 0,
    NATIVE_FIBER_RUNNING = 1,
    NATIVE_FIBER_SUSPENDED = 2,
    NATIVE_FIBER_RETURNED = 3,
    NATIVE_FIBER_CANCELLED = 4,
} native_fiber_state_t;

#if defined(__x86_64__) || defined(_M_X64)
typedef struct {
    uintptr_t sp;
    uintptr_t rbx;
    uintptr_t rbp;
    uintptr_t r12;
    uintptr_t r13;
    uintptr_t r14;
    uintptr_t r15;
} native_fiber_context_t;
#elif defined(__aarch64__) || defined(_M_ARM64)
typedef struct {
    uintptr_t sp;
    uintptr_t x19;
    uintptr_t x20;
    uintptr_t x21;
    uintptr_t x22;
    uintptr_t x23;
    uintptr_t x24;
    uintptr_t x25;
    uintptr_t x26;
    uintptr_t x27;
    uintptr_t x28;
    uintptr_t x29;
    uintptr_t x30;
    uint64_t d8;
    uint64_t d9;
    uint64_t d10;
    uint64_t d11;
    uint64_t d12;
    uint64_t d13;
    uint64_t d14;
    uint64_t d15;
} native_fiber_context_t;
#else
#error "Wasmoon native fibers require x86_64 or AArch64"
#endif

typedef struct native_fiber {
    native_fiber_context_t context;
    native_fiber_context_t caller;
    void *mapping;
    size_t mapping_size;
    size_t guard_size;
    size_t usable_size;
    native_fiber_entry_fn entry;
    void *closure;
    int owns_closure;
    pthread_t owner_thread;
    native_fiber_state_t state;
    int64_t resume_value;
    int64_t yielded_value;
    int64_t return_value;
    jit_trap_activation_t *detached_activation;
    void *parked_gc_roots;
    const void *caller_stack_bottom;
    size_t caller_stack_size;
} native_fiber_t;

typedef struct {
    native_fiber_t *fiber;
    void *jit_context;
    int64_t trampoline_ptr;
    int64_t func_ptr;
    int64_t *values;
    int values_len;
} native_jit_continuation_t;

extern void wasmoon_native_fiber_swap(
    native_fiber_context_t *from,
    const native_fiber_context_t *to
);
extern int64_t wasmoon_jit_context_ptr(void *managed);
extern int wasmoon_jit_call_trampoline(
    int64_t trampoline_ptr,
    int64_t ctx_ptr,
    int64_t func_ptr,
    int64_t *values_vec,
    int values_len
);
extern int32_t wasmoon_jit_hostcall(
    jit_context_t *ctx,
    int32_t func_idx,
    int64_t values_ptr,
    int32_t num_args,
    int32_t num_results
);

static __thread native_fiber_t *current_native_fiber = NULL;

static int fiber_on_owner_thread(const native_fiber_t *fiber) {
    return fiber && pthread_equal(fiber->owner_thread, pthread_self());
}

static void native_fiber_swap_stacks(
    native_fiber_context_t *from,
    const native_fiber_context_t *to,
    const void *target_stack_bottom,
    size_t target_stack_size,
    int is_finishing,
    const void **old_stack_bottom,
    size_t *old_stack_size
) {
#if defined(WASMOON_ADDRESS_SANITIZER)
    void *fake_stack = NULL;
    __sanitizer_start_switch_fiber(
        is_finishing ? NULL : &fake_stack,
        target_stack_bottom,
        target_stack_size
    );
    wasmoon_native_fiber_swap(from, to);
    __sanitizer_finish_switch_fiber(
        fake_stack,
        old_stack_bottom,
        old_stack_size
    );
#else
    (void)target_stack_bottom;
    (void)target_stack_size;
    (void)is_finishing;
    (void)old_stack_bottom;
    (void)old_stack_size;
    wasmoon_native_fiber_swap(from, to);
#endif
}

static void release_fiber_stack(native_fiber_t *fiber) {
    if (!fiber || !fiber->mapping) return;
    munmap(fiber->mapping, fiber->mapping_size);
    fiber->mapping = NULL;
    fiber->mapping_size = 0;
    fiber->guard_size = 0;
    fiber->usable_size = 0;
    memset(&fiber->context, 0, sizeof(fiber->context));
}

static void unregister_fiber_parked_roots(native_fiber_t *fiber) {
    if (!fiber || !fiber->parked_gc_roots) return;
    jit_parked_gc_roots_unregister(fiber->parked_gc_roots);
    fiber->parked_gc_roots = NULL;
}

static WASMOON_NO_ADDRESS_SANITIZE void fiber_bootstrap(void) {
#if defined(WASMOON_ADDRESS_SANITIZER)
    const void *caller_stack_bottom = NULL;
    size_t caller_stack_size = 0;
    __sanitizer_finish_switch_fiber(
        NULL,
        &caller_stack_bottom,
        &caller_stack_size
    );
#endif
    native_fiber_t *fiber = current_native_fiber;
    if (!fiber || fiber->state != NATIVE_FIBER_RUNNING || !fiber->entry) {
        abort();
    }
#if defined(WASMOON_ADDRESS_SANITIZER)
    fiber->caller_stack_bottom = caller_stack_bottom;
    fiber->caller_stack_size = caller_stack_size;
#endif
    fiber->return_value = call_native_fiber_entry(
        fiber->entry, fiber->closure
    );
    fiber->state = NATIVE_FIBER_RETURNED;
    native_fiber_swap_stacks(
        &fiber->context,
        &fiber->caller,
        fiber->caller_stack_bottom,
        fiber->caller_stack_size,
        1,
        NULL,
        NULL
    );
    abort();
}

static native_fiber_t *allocate_fiber(
    native_fiber_entry_fn entry,
    void *closure,
    int owns_closure,
    int64_t requested_stack_size
) {
    if (!entry || requested_stack_size <= 0) return NULL;
    long page_value = sysconf(_SC_PAGESIZE);
    if (page_value <= 0) return NULL;
    size_t page_size = (size_t)page_value;
    size_t requested = (size_t)requested_stack_size;
    if (requested < 64 * 1024) requested = 64 * 1024;
    if (requested > SIZE_MAX - page_size) return NULL;
    size_t usable_size = (requested + page_size - 1) / page_size * page_size;
    size_t mapping_size = page_size + usable_size;
    void *mapping = mmap(
        NULL,
        mapping_size,
        PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANONYMOUS,
        -1,
        0
    );
    if (mapping == MAP_FAILED) return NULL;
    if (mprotect(mapping, page_size, PROT_NONE) != 0) {
        munmap(mapping, mapping_size);
        return NULL;
    }

    native_fiber_t *fiber = (native_fiber_t *)calloc(1, sizeof(native_fiber_t));
    if (!fiber) {
        munmap(mapping, mapping_size);
        return NULL;
    }
    fiber->mapping = mapping;
    fiber->mapping_size = mapping_size;
    fiber->guard_size = page_size;
    fiber->usable_size = usable_size;
    fiber->entry = entry;
    fiber->closure = closure;
    fiber->owns_closure = owns_closure;
    fiber->owner_thread = pthread_self();
    fiber->state = NATIVE_FIBER_READY;

    uintptr_t stack_top = (uintptr_t)mapping + mapping_size;
#if defined(__x86_64__) || defined(_M_X64)
    stack_top &= ~(uintptr_t)0xF;
    stack_top -= sizeof(uintptr_t);
    *(uintptr_t *)stack_top = (uintptr_t)abort;
    stack_top -= sizeof(uintptr_t);
    *(uintptr_t *)stack_top = (uintptr_t)fiber_bootstrap;
    fiber->context.sp = stack_top;
#elif defined(__aarch64__) || defined(_M_ARM64)
    stack_top &= ~(uintptr_t)0xF;
    fiber->context.sp = stack_top;
    fiber->context.x30 = (uintptr_t)fiber_bootstrap;
#endif
    return fiber;
}

static void destroy_fiber(native_fiber_t *fiber) {
    if (!fiber) return;
    if (fiber->state == NATIVE_FIBER_RUNNING) return;
    unregister_fiber_parked_roots(fiber);
    jit_trap_activation_abandon(fiber->detached_activation);
    fiber->detached_activation = NULL;
    release_fiber_stack(fiber);
    if (fiber->owns_closure && fiber->closure) {
        moonbit_decref(fiber->closure);
        fiber->closure = NULL;
    }
    free(fiber);
}

static void finalize_native_fiber(void *self) {
    native_fiber_t **slot = (native_fiber_t **)self;
    if (!slot || !*slot) return;
    destroy_fiber(*slot);
    *slot = NULL;
}

static native_fiber_t *managed_fiber_ptr(void *managed) {
    if (!managed) return NULL;
    return *(native_fiber_t **)managed;
}

static int64_t native_jit_continuation_entry(void *closure) {
    native_jit_continuation_t *continuation =
        (native_jit_continuation_t *)closure;
    return wasmoon_jit_call_trampoline(
        continuation->trampoline_ptr,
        wasmoon_jit_context_ptr(continuation->jit_context),
        continuation->func_ptr,
        continuation->values,
        continuation->values_len
    );
}

static void finalize_native_jit_continuation(void *self) {
    native_jit_continuation_t *continuation =
        (native_jit_continuation_t *)self;
    destroy_fiber(continuation->fiber);
    continuation->fiber = NULL;
    if (continuation->jit_context) {
        moonbit_decref(continuation->jit_context);
        continuation->jit_context = NULL;
    }
    if (continuation->values) {
        moonbit_decref(continuation->values);
        continuation->values = NULL;
    }
}

MOONBIT_FFI_EXPORT void *wasmoon_native_fiber_alloc(
    native_fiber_entry_fn entry,
    void *closure,
    int64_t stack_size
) {
    native_fiber_t *fiber = allocate_fiber(entry, closure, 1, stack_size);
    if (!fiber) {
        if (closure) moonbit_decref(closure);
        return NULL;
    }
    native_fiber_t **managed = (native_fiber_t **)moonbit_make_external_object(
        finalize_native_fiber,
        sizeof(native_fiber_t *)
    );
    if (!managed) {
        destroy_fiber(fiber);
        return NULL;
    }
    *managed = fiber;
    return managed;
}

MOONBIT_FFI_EXPORT void *wasmoon_native_jit_continuation_alloc(
    void *jit_context,
    int64_t trampoline_ptr,
    int64_t func_ptr,
    int64_t *values,
    int values_len,
    int64_t stack_size
) {
    native_jit_continuation_t *continuation =
        (native_jit_continuation_t *)moonbit_make_external_object(
            finalize_native_jit_continuation,
            sizeof(native_jit_continuation_t)
        );
    if (!continuation) {
        if (jit_context) moonbit_decref(jit_context);
        if (values) moonbit_decref(values);
        return NULL;
    }
    memset(continuation, 0, sizeof(*continuation));
    continuation->jit_context = jit_context;
    continuation->trampoline_ptr = trampoline_ptr;
    continuation->func_ptr = func_ptr;
    continuation->values = values;
    continuation->values_len = values_len;
    continuation->fiber = allocate_fiber(
        native_jit_continuation_entry,
        continuation,
        0,
        stack_size
    );
    if (!continuation->fiber) {
        finalize_native_jit_continuation(continuation);
        return NULL;
    }
    return continuation;
}

MOONBIT_FFI_EXPORT int wasmoon_native_fiber_continue(
    void *managed,
    int64_t resume_value
) {
    native_fiber_t *fiber = managed_fiber_ptr(managed);
    if (!fiber) return -1;
    if (!fiber_on_owner_thread(fiber)) return -2;
    if (fiber->state != NATIVE_FIBER_READY &&
        fiber->state != NATIVE_FIBER_SUSPENDED) {
        return -3;
    }
    native_fiber_t *previous = current_native_fiber;
    current_native_fiber = fiber;
    fiber->resume_value = resume_value;
    fiber->state = NATIVE_FIBER_RUNNING;
    native_fiber_swap_stacks(
        &fiber->caller,
        &fiber->context,
        (const unsigned char *)fiber->mapping + fiber->guard_size,
        fiber->usable_size,
        0,
        NULL,
        NULL
    );
    current_native_fiber = previous;
    if (fiber->state == NATIVE_FIBER_SUSPENDED) return 0;
    if (fiber->state == NATIVE_FIBER_RETURNED) return 1;
    return -4;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_native_fiber_yield(int64_t value) {
    native_fiber_t *fiber = current_native_fiber;
    if (!fiber || fiber->state != NATIVE_FIBER_RUNNING) return INT64_MIN;
    fiber->yielded_value = value;
    fiber->state = NATIVE_FIBER_SUSPENDED;
    fiber->detached_activation = jit_trap_activation_detach();
    if (!jit_parked_gc_roots_register(
            fiber->detached_activation,
            &fiber->parked_gc_roots
        )) {
        jit_trap_activation_attach(fiber->detached_activation);
        fiber->detached_activation = NULL;
        fiber->state = NATIVE_FIBER_RUNNING;
        return INT64_MIN;
    }
    native_fiber_swap_stacks(
        &fiber->context,
        &fiber->caller,
        fiber->caller_stack_bottom,
        fiber->caller_stack_size,
        0,
        &fiber->caller_stack_bottom,
        &fiber->caller_stack_size
    );
    unregister_fiber_parked_roots(fiber);
    jit_trap_activation_attach(fiber->detached_activation);
    fiber->detached_activation = NULL;
    if (fiber->state != NATIVE_FIBER_RUNNING) return INT64_MIN;
    return fiber->resume_value;
}

MOONBIT_FFI_EXPORT int wasmoon_native_fiber_cancel(void *managed) {
    native_fiber_t *fiber = managed_fiber_ptr(managed);
    if (!fiber) return -1;
    if (!fiber_on_owner_thread(fiber)) return -2;
    if (fiber->state != NATIVE_FIBER_READY &&
        fiber->state != NATIVE_FIBER_SUSPENDED) {
        return -3;
    }
    fiber->state = NATIVE_FIBER_CANCELLED;
    unregister_fiber_parked_roots(fiber);
    jit_trap_activation_abandon(fiber->detached_activation);
    fiber->detached_activation = NULL;
    release_fiber_stack(fiber);
    if (fiber->owns_closure && fiber->closure) {
        moonbit_decref(fiber->closure);
        fiber->closure = NULL;
    }
    return 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_native_hostcall_suspend_event(void) {
    return WASMOON_FIBER_EVENT_HOSTCALL_SUSPENDED;
}

MOONBIT_FFI_EXPORT int wasmoon_native_fiber_state(void *managed) {
    native_fiber_t *fiber = managed_fiber_ptr(managed);
    return fiber ? (int)fiber->state : -1;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_native_fiber_yielded_value(void *managed) {
    native_fiber_t *fiber = managed_fiber_ptr(managed);
    return fiber ? fiber->yielded_value : 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_native_fiber_return_value(void *managed) {
    native_fiber_t *fiber = managed_fiber_ptr(managed);
    return fiber ? fiber->return_value : 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_native_fiber_stack_size(void *managed) {
    native_fiber_t *fiber = managed_fiber_ptr(managed);
    return fiber ? (int64_t)fiber->usable_size : 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_native_fiber_guard_size(void *managed) {
    native_fiber_t *fiber = managed_fiber_ptr(managed);
    return fiber ? (int64_t)fiber->guard_size : 0;
}

int wasmoon_native_fiber_stack_bounds(
    uintptr_t *stack_base,
    uintptr_t *stack_top,
    uintptr_t *guard_base,
    size_t *guard_size
) {
    native_fiber_t *fiber = current_native_fiber;
    if (!fiber || !fiber->mapping) return 0;
    if (stack_base) {
        *stack_base = (uintptr_t)fiber->mapping + fiber->guard_size;
    }
    if (stack_top) {
        *stack_top = (uintptr_t)fiber->mapping + fiber->mapping_size;
    }
    if (guard_base) *guard_base = (uintptr_t)fiber->mapping;
    if (guard_size) *guard_size = fiber->guard_size;
    return 1;
}
