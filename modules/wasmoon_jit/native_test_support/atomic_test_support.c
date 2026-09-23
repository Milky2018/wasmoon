#include "../jit_ffi/jit_internal.h"
#ifdef _WIN32
#include <process.h>
typedef HANDLE test_thread;
#define WORKER_RESULT unsigned __stdcall
#define WORKER_DONE 0
static int start_worker(test_thread *thread, unsigned (__stdcall *entry)(void *), void *argument) {
    *thread = (HANDLE)_beginthreadex(NULL, 0, entry, argument, 0, NULL);
    return *thread == NULL;
}
static void join_worker(test_thread thread) {
    WaitForSingleObject(thread, INFINITE);
    CloseHandle(thread);
}
static void yield_worker(void) { SwitchToThread(); }
#else
#include <pthread.h>
#include <sched.h>
typedef pthread_t test_thread;
#define WORKER_RESULT void *
#define WORKER_DONE NULL
static int start_worker(test_thread *thread, void *(*entry)(void *), void *argument) {
    return pthread_create(thread, NULL, entry, argument);
}
static void join_worker(test_thread thread) { pthread_join(thread, NULL); }
static void yield_worker(void) { sched_yield(); }
#endif

extern int32_t wasmoon_atomic_notify(int64_t, int64_t, int32_t);
extern void wasmoon_jit_retain_memory_desc(int64_t);
extern void wasmoon_jit_free_memory_desc(int64_t);

MOONBIT_FFI_EXPORT int64_t wasmoon_test_memory_owner_count(int64_t descriptor) {
    wasmoon_memory_t *memory = (void *)(uintptr_t)descriptor;
    return (int64_t)atomic_load_explicit(&memory->owners, memory_order_relaxed);
}

typedef struct {
    test_thread thread;
    int64_t descriptor;
    int64_t offset;
    int32_t result;
} atomic_notify_worker;

static WORKER_RESULT run_atomic_notify(void *argument) {
    atomic_notify_worker *worker = argument;
    for (int attempt = 0; attempt < 1000000; attempt++) {
        int32_t result = wasmoon_atomic_notify(worker->descriptor, worker->offset, 1);
        if (result) {
            worker->result = result;
            return WORKER_DONE;
        }
        yield_worker();
    }
    worker->result = -1;
    return WORKER_DONE;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_test_atomic_notify_start(int64_t descriptor, int64_t offset) {
    atomic_notify_worker *worker = calloc(1, sizeof(*worker));
    if (!worker) return 0;
    worker->descriptor = descriptor;
    worker->offset = offset;
    wasmoon_jit_retain_memory_desc(descriptor);
    if (start_worker(&worker->thread, run_atomic_notify, worker)) {
        wasmoon_jit_free_memory_desc(descriptor);
        free(worker);
        return 0;
    }
    return (int64_t)(uintptr_t)worker;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_test_atomic_notify_finish(int64_t pointer) {
    atomic_notify_worker *worker = (void *)(uintptr_t)pointer;
    if (!worker) return -1;
    join_worker(worker->thread);
    int32_t result = worker->result;
    wasmoon_jit_free_memory_desc(worker->descriptor);
    free(worker);
    return result;
}

// This worker never enters MoonBit. The test owns the memory descriptor until
// join/cancel completes, so concurrent work touches only native atomic storage.
typedef struct {
    test_thread thread;
    uint8_t *base;
    int32_t width;
    int32_t iterations;
    _Atomic int32_t cancelled;
} atomic_counter_worker;

static WORKER_RESULT run_atomic_counter(void *argument) {
    atomic_counter_worker *worker = argument;
    _Atomic uint32_t *start = (_Atomic uint32_t *)(worker->base + 16);
    while (!atomic_load_explicit(start, memory_order_seq_cst)) {
        if (atomic_load_explicit(&worker->cancelled, memory_order_seq_cst)) return WORKER_DONE;
        yield_worker();
    }
    atomic_store_explicit((_Atomic uint32_t *)(worker->base + 20), 1, memory_order_seq_cst);
    for (int32_t i = 0; i < worker->iterations; i++) {
        if (atomic_load_explicit(&worker->cancelled, memory_order_seq_cst)) break;
        if (worker->width == 4) {
            atomic_fetch_add_explicit((_Atomic uint32_t *)worker->base, 1, memory_order_seq_cst);
        } else {
            atomic_fetch_add_explicit((_Atomic uint64_t *)worker->base, 1, memory_order_seq_cst);
        }
    }
    return WORKER_DONE;
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
    if (start_worker(&worker->thread, run_atomic_counter, worker)) {
        free(worker);
        return 0;
    }
    return (int64_t)(uintptr_t)worker;
}

MOONBIT_FFI_EXPORT void wasmoon_test_atomic_counter_finish(int64_t pointer, int32_t cancel) {
    atomic_counter_worker *worker = (atomic_counter_worker *)(uintptr_t)pointer;
    if (!worker) return;
    if (cancel) atomic_store_explicit(&worker->cancelled, 1, memory_order_seq_cst);
    join_worker(worker->thread);
    free(worker);
}

// A native growth participant that records each returned old size. The final
// growth happens after the guest's last growth, exposing stale JIT size caches.
typedef struct {
    test_thread thread;
    wasmoon_memory_t *memory;
    int32_t iterations;
    _Atomic int32_t cancelled;
    int64_t sum;
} memory_growth_worker;

static int growth_wait(memory_growth_worker *worker, size_t offset) {
    while (!atomic_load_explicit((_Atomic uint32_t *)(worker->memory->base + offset), memory_order_seq_cst)) {
        if (atomic_load_explicit(&worker->cancelled, memory_order_seq_cst)) return 0;
        yield_worker();
    }
    return 1;
}

static WORKER_RESULT run_memory_growth(void *argument) {
    memory_growth_worker *worker = argument;
    uint8_t *original_base = worker->memory->base;
    if (!growth_wait(worker, 16)) return WORKER_DONE;
    atomic_store_explicit((_Atomic uint32_t *)(original_base + 20), 1, memory_order_seq_cst);
    for (int32_t i = 0; i <= worker->iterations; i++) {
        if (atomic_load_explicit(&worker->cancelled, memory_order_seq_cst)) return WORKER_DONE;
        if (i == worker->iterations && !growth_wait(worker, 24)) return WORKER_DONE;
        int64_t old = memory_grow_desc_internal(worker->memory, 1, -1);
        if (old < 0 || worker->memory->base != original_base) {
            worker->sum = -1;
            atomic_store_explicit((_Atomic uint32_t *)(worker->memory->base + 28), 1, memory_order_seq_cst);
            return WORKER_DONE;
        }
        worker->sum += old;
    }
    atomic_store_explicit((_Atomic uint32_t *)(original_base + 28), 1, memory_order_seq_cst);
    return WORKER_DONE;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_test_memory_growth_start(int64_t descriptor, int32_t iterations) {
    wasmoon_memory_t *memory = (wasmoon_memory_t *)(uintptr_t)descriptor;
    if (!memory || !memory->is_shared || iterations <= 0) return 0;
    memory_growth_worker *worker = calloc(1, sizeof(*worker));
    if (!worker) return 0;
    worker->memory = memory;
    worker->iterations = iterations;
    if (start_worker(&worker->thread, run_memory_growth, worker)) {
        free(worker);
        return 0;
    }
    return (int64_t)(uintptr_t)worker;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_test_memory_growth_finish(int64_t pointer, int32_t cancel) {
    memory_growth_worker *worker = (memory_growth_worker *)(uintptr_t)pointer;
    if (!worker) return 0;
    if (cancel) atomic_store_explicit(&worker->cancelled, 1, memory_order_seq_cst);
    join_worker(worker->thread);
    int64_t result = worker->sum;
    free(worker);
    return result;
}
