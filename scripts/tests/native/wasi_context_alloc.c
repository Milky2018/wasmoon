// Inject each allocation failure into the production context initializer.
#include <assert.h>
#include <stdlib.h>
#include "jit_internal.h"

static int allocation_index;
static int fail_at;
static int live_allocations;

static void *checked_malloc(size_t size) {
    if (++allocation_index == fail_at) return NULL;
    void *value = malloc(size);
    if (value) live_allocations++;
    return value;
}
static void *checked_calloc(size_t count, size_t size) {
    if (++allocation_index == fail_at) return NULL;
    void *value = calloc(count, size);
    if (value) live_allocations++;
    return value;
}
static void checked_free(void *value) {
    if (value) live_allocations--;
    free(value);
}
#define malloc checked_malloc
#define calloc checked_calloc
#define free checked_free
#include "wasi_context.c"
#undef malloc
#undef calloc
#undef free

// These runtime services are not invoked by descriptor initialization.
moonbit_bytes_t moonbit_make_bytes(int32_t size, int value) {
    (void)size; (void)value; abort();
}
void moonbit_decref(void *value) { (void)value; abort(); }
void moonbit_incref(void *value) { (void)value; abort(); }
int64_t wasmoon_jit_context_ptr(void *value) { return (int64_t)(uintptr_t)value; }

int main(void) {
    for (int quiet = 0; quiet < 2; quiet++) {
        for (fail_at = 1; fail_at <= 9; fail_at++) {
            jit_context_t context = {0};
            allocation_index = 0;
            if (quiet) wasmoon_jit_init_wasi_fds_quiet((int64_t)(uintptr_t)&context, 2);
            else wasmoon_jit_init_wasi_fds((int64_t)(uintptr_t)&context, 2);
            wasmoon_jit_free_wasi_fds((int64_t)(uintptr_t)&context);
            wasmoon_jit_free_wasi_fds((int64_t)(uintptr_t)&context);
            assert(live_allocations == 0);
        }
    }
    jit_context_t context = {0};
    fail_at = 0;
    wasmoon_jit_init_wasi_fds((int64_t)(uintptr_t)&context, 2);
    wasmoon_jit_init_wasi_fds((int64_t)(uintptr_t)&context, 1);
    wasmoon_jit_free_wasi_fds((int64_t)(uintptr_t)&context);
    assert(live_allocations == 0);
    return 0;
}
