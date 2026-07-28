#include "jit_internal.h"

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

typedef int64_t (*native_fiber_entry_fn)(void *closure);

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
} native_fiber_t;

extern void wasmoon_native_fiber_swap(
    native_fiber_context_t *from,
    const native_fiber_context_t *to
);

static __thread native_fiber_t *current_native_fiber = NULL;

static int64_t register_test_entry(void *closure);

static int fiber_on_owner_thread(const native_fiber_t *fiber) {
    return fiber && pthread_equal(fiber->owner_thread, pthread_self());
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

static void fiber_bootstrap(void) {
    native_fiber_t *fiber = current_native_fiber;
    if (!fiber || fiber->state != NATIVE_FIBER_RUNNING || !fiber->entry) {
        abort();
    }
    fiber->return_value = fiber->entry(fiber->closure);
    fiber->state = NATIVE_FIBER_RETURNED;
    wasmoon_native_fiber_swap(&fiber->context, &fiber->caller);
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
    wasmoon_native_fiber_swap(&fiber->caller, &fiber->context);
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
    wasmoon_native_fiber_swap(&fiber->context, &fiber->caller);
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
    release_fiber_stack(fiber);
    if (fiber->owns_closure && fiber->closure) {
        moonbit_decref(fiber->closure);
        fiber->closure = NULL;
    }
    return 0;
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

MOONBIT_FFI_EXPORT int wasmoon_native_fiber_guard_test(void) {
    native_fiber_t *fiber = allocate_fiber(
        register_test_entry,
        NULL,
        0,
        64 * 1024
    );
    if (!fiber) return 0;
    pid_t child = fork();
    if (child < 0) {
        destroy_fiber(fiber);
        return 0;
    }
    if (child == 0) {
        volatile unsigned char *guard =
            (volatile unsigned char *)fiber->mapping;
        *guard = 1;
        _exit(0);
    }
    int status = 0;
    int waited = waitpid(child, &status, 0);
    destroy_fiber(fiber);
    return waited == child && WIFSIGNALED(status);
}

static int64_t register_test_entry(void *closure) {
    (void)closure;
#if defined(__aarch64__) || defined(_M_ARM64)
    uint64_t integer_after = 0;
    uint64_t float_after = 0;
    const uint64_t integer_before = UINT64_C(0x1938574628193746);
    const uint64_t float_before = UINT64_C(0x406EDD2F1A9FBE77);
    __asm__ volatile(
        "mov x19, %0\n\t"
        "fmov d8, %1\n\t"
        :
        : "r"(integer_before), "r"(float_before)
        : "x19", "d8"
    );
    wasmoon_native_fiber_yield(1);
    __asm__ volatile(
        "mov %0, x19\n\t"
        "fmov %1, d8\n\t"
        : "=r"(integer_after), "=r"(float_after)
    );
    return integer_after == integer_before && float_after == float_before;
#elif defined(__x86_64__) || defined(_M_X64)
    uint64_t after = 0;
    const uint64_t before = UINT64_C(0x1938574628193746);
    __asm__ volatile("movq %0, %%r12" : : "r"(before) : "r12");
    wasmoon_native_fiber_yield(1);
    __asm__ volatile("movq %%r12, %0" : "=r"(after));
    return after == before;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_native_fiber_register_test(void) {
    native_fiber_t *fiber = allocate_fiber(register_test_entry, NULL, 0, 64 * 1024);
    if (!fiber) return 0;
    native_fiber_t *previous = current_native_fiber;
    current_native_fiber = fiber;
    fiber->state = NATIVE_FIBER_RUNNING;
    wasmoon_native_fiber_swap(&fiber->caller, &fiber->context);
    if (fiber->state != NATIVE_FIBER_SUSPENDED) {
        current_native_fiber = previous;
        destroy_fiber(fiber);
        return 0;
    }
    fiber->state = NATIVE_FIBER_RUNNING;
    wasmoon_native_fiber_swap(&fiber->caller, &fiber->context);
    current_native_fiber = previous;
    int passed = fiber->state == NATIVE_FIBER_RETURNED &&
        fiber->return_value == 1;
    destroy_fiber(fiber);
    return passed;
}
