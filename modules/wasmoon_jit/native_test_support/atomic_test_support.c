#include "../jit_ffi/jit_internal.h"
#include <pthread.h>
#include <sched.h>

// This worker never enters MoonBit. The test owns the memory descriptor until
// join/cancel completes, so concurrent work touches only native atomic storage.
typedef struct {
    pthread_t thread;
    uint8_t *base;
    int32_t width;
    int32_t iterations;
    int32_t cancelled;
} atomic_counter_worker;

static void *run_atomic_counter(void *argument) {
    atomic_counter_worker *worker = argument;
    uint32_t *start = (uint32_t *)(worker->base + 16);
    while (!__atomic_load_n(start, __ATOMIC_SEQ_CST)) {
        if (__atomic_load_n(&worker->cancelled, __ATOMIC_SEQ_CST)) return NULL;
        sched_yield();
    }
    __atomic_store_n((uint32_t *)(worker->base + 20), 1, __ATOMIC_SEQ_CST);
    for (int32_t i = 0; i < worker->iterations; i++) {
        if (__atomic_load_n(&worker->cancelled, __ATOMIC_SEQ_CST)) break;
        if (worker->width == 4) {
            __atomic_fetch_add((uint32_t *)worker->base, 1, __ATOMIC_SEQ_CST);
        } else {
            __atomic_fetch_add((uint64_t *)worker->base, 1, __ATOMIC_SEQ_CST);
        }
    }
    return NULL;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_test_atomic_counter_start(
    int64_t descriptor, int32_t width, int32_t iterations
) {
    wasmoon_memory_t *memory = (wasmoon_memory_t *)(uintptr_t)descriptor;
    if (!memory || (width != 4 && width != 8) || iterations <= 0) return 0;
    atomic_counter_worker *worker = calloc(1, sizeof(*worker));
    if (!worker) return 0;
    worker->base = memory->base;
    worker->width = width;
    worker->iterations = iterations;
    if (pthread_create(&worker->thread, NULL, run_atomic_counter, worker)) {
        free(worker);
        return 0;
    }
    return (int64_t)(uintptr_t)worker;
}

MOONBIT_FFI_EXPORT void wasmoon_test_atomic_counter_finish(int64_t pointer, int32_t cancel) {
    atomic_counter_worker *worker = (atomic_counter_worker *)(uintptr_t)pointer;
    if (!worker) return;
    if (cancel) __atomic_store_n(&worker->cancelled, 1, __ATOMIC_SEQ_CST);
    pthread_join(worker->thread, NULL);
    free(worker);
}
