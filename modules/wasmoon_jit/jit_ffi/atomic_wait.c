// Wait queues contain only native state and retain the shared memory owner.
#include "jit_internal.h"
#include <time.h>

extern void wasmoon_jit_retain_memory_desc(int64_t);
extern void wasmoon_jit_free_memory_desc(int64_t);
extern int64_t wasmoon_memory_atomic_load(int64_t, int64_t, int32_t);

typedef struct atomic_waiter {
    struct atomic_waiter *next;
    struct atomic_waiter *previous;
    int64_t descriptor;
    int64_t offset;
    uint64_t deadline;
    int32_t result; // -1 pending, 0 notified, 1 unequal, 2 timeout, 3 cancelled
    int queued;
    int finite;
} atomic_waiter;

static atomic_flag wait_lock = ATOMIC_FLAG_INIT;
static atomic_waiter *waiters;
static atomic_waiter *waiters_tail;

static void lock_waiters(void) {
    while (atomic_flag_test_and_set_explicit(&wait_lock, memory_order_acquire)) {}
}

static void unlock_waiters(void) {
    atomic_flag_clear_explicit(&wait_lock, memory_order_release);
}

static uint64_t monotonic_nanos(void) {
#ifdef _WIN32
    LARGE_INTEGER counter, frequency;
    if (!QueryPerformanceCounter(&counter) || !QueryPerformanceFrequency(&frequency)) abort();
    uint64_t ticks = (uint64_t)counter.QuadPart;
    uint64_t hz = (uint64_t)frequency.QuadPart;
    return ticks / hz * 1000000000ULL + ticks % hz * 1000000000ULL / hz;
#else
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now)) abort();
    return (uint64_t)now.tv_sec * 1000000000ULL + (uint64_t)now.tv_nsec;
#endif
}

static void unlink_waiter(atomic_waiter *waiter) {
    if (!waiter->queued) return;
    if (waiter->previous) waiter->previous->next = waiter->next;
    else waiters = waiter->next;
    if (waiter->next) waiter->next->previous = waiter->previous;
    else waiters_tail = waiter->previous;
    waiter->next = NULL;
    waiter->previous = NULL;
    waiter->queued = 0;
}

static void expire_waiter(atomic_waiter *waiter, uint64_t now) {
    if (waiter->result == -1 && waiter->finite && now >= waiter->deadline) {
        unlink_waiter(waiter);
        waiter->result = 2;
    }
}

// The caller has checked sharedness, bounds and natural alignment and owns
// the descriptor until this function returns. No MoonBit callback runs here.
MOONBIT_FFI_EXPORT void *wasmoon_atomic_wait_begin(
    int64_t descriptor, int64_t offset, int32_t width,
    int64_t expected, int64_t timeout
) {
    atomic_waiter *waiter = calloc(1, sizeof(*waiter));
    if (!waiter) return NULL;
    waiter->descriptor = descriptor;
    waiter->offset = offset;
    waiter->result = -1;
    wasmoon_jit_retain_memory_desc(descriptor);
    lock_waiters();
    int64_t actual = wasmoon_memory_atomic_load(descriptor, offset, width);
    int equal = width == 4 ? (uint32_t)actual == (uint32_t)expected : actual == expected;
    if (!equal) {
        waiter->result = 1;
    } else if (timeout == 0) {
        waiter->result = 2;
    } else {
        waiter->finite = timeout > 0;
        if (waiter->finite) {
            uint64_t now = monotonic_nanos();
            waiter->deadline = UINT64_MAX - now < (uint64_t)timeout
                ? UINT64_MAX : now + (uint64_t)timeout;
        }
        waiter->previous = waiters_tail;
        if (waiters_tail) waiters_tail->next = waiter;
        else waiters = waiter;
        waiters_tail = waiter;
        waiter->queued = 1;
    }
    unlock_waiters();
    return waiter;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_atomic_wait_poll(void *raw) {
    atomic_waiter *waiter = raw;
    lock_waiters();
    expire_waiter(waiter, monotonic_nanos());
    int32_t result = waiter->result;
    unlock_waiters();
    return result;
}

MOONBIT_FFI_EXPORT void wasmoon_atomic_wait_destroy(void *raw) {
    atomic_waiter *waiter = raw;
    if (!waiter) return;
    lock_waiters();
    unlink_waiter(waiter);
    unlock_waiters();
    wasmoon_jit_free_memory_desc(waiter->descriptor);
    free(waiter);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_atomic_notify(
    int64_t descriptor, int64_t offset, int32_t count_bits
) {
    uint32_t remaining = (uint32_t)count_bits;
    uint32_t notified = 0;
    lock_waiters();
    uint64_t now = monotonic_nanos();
    for (atomic_waiter *waiter = waiters, *next; waiter && remaining; waiter = next) {
        next = waiter->next;
        if (waiter->descriptor != descriptor || waiter->offset != offset) continue;
        expire_waiter(waiter, now);
        if (waiter->result != -1) continue;
        unlink_waiter(waiter);
        waiter->result = 0;
        remaining--;
        notified++;
    }
    unlock_waiters();
    return (int32_t)notified;
}

static void finalize_managed_waiter(void *object) {
    atomic_waiter **managed = object;
    wasmoon_atomic_wait_destroy(*managed);
    *managed = NULL;
}

MOONBIT_FFI_EXPORT void *wasmoon_atomic_wait_managed(
    int64_t descriptor, int64_t offset, int32_t width,
    int64_t expected, int64_t timeout
) {
    atomic_waiter **managed = moonbit_make_external_object(
        finalize_managed_waiter, sizeof(*managed)
    );
    *managed = wasmoon_atomic_wait_begin(descriptor, offset, width, expected, timeout);
    return managed;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_atomic_wait_managed_poll(void *object) {
    atomic_waiter *waiter = *(atomic_waiter **)object;
    return waiter ? wasmoon_atomic_wait_poll(waiter) : 3;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_atomic_wait_managed_allocated(void *object) {
    return *(atomic_waiter **)object != NULL;
}

MOONBIT_FFI_EXPORT void wasmoon_atomic_wait_pause(void *object) {
    atomic_waiter *waiter = *(atomic_waiter **)object;
    if (!waiter || wasmoon_atomic_wait_poll(waiter) != -1) return;
#ifdef _WIN32
    Sleep(1);
#else
    struct timespec delay = {0, 1000000};
    nanosleep(&delay, NULL);
#endif
}

MOONBIT_FFI_EXPORT void wasmoon_atomic_wait_managed_cancel(void *object) {
    finalize_managed_waiter(object);
}

int32_t wasmoon_atomic_wait_guest(
    jit_context_t *ctx, int64_t descriptor, int64_t offset,
    int32_t width, int64_t expected, int64_t timeout
) {
    void *waiter = wasmoon_atomic_wait_begin(descriptor, offset, width, expected, timeout);
    if (!waiter) {
        g_trap_code = 9;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return 9;
    }
    int fiber_owned = wasmoon_native_fiber_own_waiter(waiter);
    int32_t result, trap = 0;
    while ((result = wasmoon_atomic_wait_poll(waiter)) == -1) {
        if (wasmoon_jit_cancellation_requested(ctx)) {
            trap = 11;
            break;
        }
        if (ctx->scheduling_budget > 0) {
            if (!fiber_owned || wasmoon_native_fiber_yield(
                    WASMOON_FIBER_EVENT_ATOMIC_WAIT
                ) == INT64_MIN) {
                trap = 8;
                break;
            }
        } else {
#ifdef _WIN32
            Sleep(1);
#else
            struct timespec delay = {0, 1000000};
            nanosleep(&delay, NULL);
#endif
        }
    }
    if (fiber_owned) wasmoon_native_fiber_release_waiter();
    else wasmoon_atomic_wait_destroy(waiter);
    if (trap) {
        g_trap_code = trap;
        if (g_trap_active) siglongjmp(g_trap_jmp_buf, 1);
        return trap;
    }
    return result;
}
