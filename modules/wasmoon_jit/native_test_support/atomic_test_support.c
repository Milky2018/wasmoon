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

// A native growth participant that records each returned old size. The final
// growth happens after the guest's last growth, exposing stale JIT size caches.
typedef struct {
    pthread_t thread;
    wasmoon_memory_t *memory;
    int32_t iterations;
    int32_t cancelled;
    int64_t sum;
} memory_growth_worker;

static int growth_wait(memory_growth_worker *worker, size_t offset) {
    while (!__atomic_load_n((uint32_t *)(worker->memory->base + offset), __ATOMIC_SEQ_CST)) {
        if (__atomic_load_n(&worker->cancelled, __ATOMIC_SEQ_CST)) return 0;
        sched_yield();
    }
    return 1;
}

static void *run_memory_growth(void *argument) {
    memory_growth_worker *worker = argument;
    uint8_t *original_base = worker->memory->base;
    if (!growth_wait(worker, 16)) return NULL;
    __atomic_store_n((uint32_t *)(original_base + 20), 1, __ATOMIC_SEQ_CST);
    for (int32_t i = 0; i <= worker->iterations; i++) {
        if (__atomic_load_n(&worker->cancelled, __ATOMIC_SEQ_CST)) return NULL;
        if (i == worker->iterations && !growth_wait(worker, 24)) return NULL;
        int32_t old = memory_grow_desc_internal(worker->memory, 1, -1);
        if (old < 0 || worker->memory->base != original_base) {
            worker->sum = -1;
            __atomic_store_n((uint32_t *)(worker->memory->base + 28), 1, __ATOMIC_SEQ_CST);
            return NULL;
        }
        worker->sum += old;
    }
    __atomic_store_n((uint32_t *)(original_base + 28), 1, __ATOMIC_SEQ_CST);
    return NULL;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_test_memory_growth_start(int64_t descriptor, int32_t iterations) {
    wasmoon_memory_t *memory = (wasmoon_memory_t *)(uintptr_t)descriptor;
    if (!memory || !memory->is_shared || iterations <= 0) return 0;
    memory_growth_worker *worker = calloc(1, sizeof(*worker));
    if (!worker) return 0;
    worker->memory = memory;
    worker->iterations = iterations;
    if (pthread_create(&worker->thread, NULL, run_memory_growth, worker)) {
        free(worker);
        return 0;
    }
    return (int64_t)(uintptr_t)worker;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_test_memory_growth_finish(int64_t pointer, int32_t cancel) {
    memory_growth_worker *worker = (memory_growth_worker *)(uintptr_t)pointer;
    if (!worker) return 0;
    if (cancel) __atomic_store_n(&worker->cancelled, 1, __ATOMIC_SEQ_CST);
    pthread_join(worker->thread, NULL);
    int64_t result = worker->sum;
    free(worker);
    return result;
}
