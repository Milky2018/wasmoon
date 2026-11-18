#ifndef WASMOON_FIBER_H
#define WASMOON_FIBER_H

#include "../context/jit_ffi.h"

int wasmoon_native_fiber_stack_bounds(
    uintptr_t *stack_base,
    uintptr_t *stack_top,
    uintptr_t *guard_base,
    size_t *guard_size
);
MOONBIT_FFI_EXPORT int64_t wasmoon_native_fiber_yield(int64_t value);

#define WASMOON_HOSTCALL_SUSPEND_STATUS (-1)
#define WASMOON_FIBER_EVENT_HOSTCALL_SUSPENDED INT64_C(0x57534d5355535001)
#define WASMOON_FIBER_EVENT_GUEST_YIELD INT64_C(0x57534d5355535002)
#define WASMOON_FIBER_EVENT_ATOMIC_WAIT INT64_C(0x57534d5355535003)

int wasmoon_native_fiber_own_waiter(void *waiter);
void wasmoon_native_fiber_release_waiter(void);

void *native_fiber_alloc_c(int64_t (*entry)(void *), void *closure, int64_t stack_size);
int native_fiber_continue_c(void *fiber, int64_t value);
void native_fiber_destroy_c(void *fiber);
void *native_fiber_gc_roots_c(void *fiber);
int64_t native_fiber_result_c(void *fiber);
int64_t native_fiber_event_c(void *fiber);

void *native_fiber_own_resource(void *resource, void (*release)(void *));
void native_fiber_replace_resource(void *scope, void *resource);
void native_fiber_disown_resource(void *scope);

int64_t native_fiber_stack_size_c(void);

MOONBIT_FFI_EXPORT void *wasmoon_native_fiber_alloc(
    int64_t (*entry)(void *), void *closure, int64_t stack_size);
MOONBIT_FFI_EXPORT int wasmoon_native_fiber_continue(void *managed, int64_t value);
MOONBIT_FFI_EXPORT int64_t wasmoon_native_fiber_return_value(void *managed);

#endif
