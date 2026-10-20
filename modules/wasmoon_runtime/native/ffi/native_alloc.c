#include "native_alloc.h"
#include <stdlib.h>
#include <moonbit.h>

#if defined(_MSC_VER) && !defined(__clang__)
static __declspec(thread) int32_t fail_after;
#else
static _Thread_local int32_t fail_after;
#endif

MOONBIT_FFI_EXPORT void wasmoon_native_fail_allocation_for_tests(int32_t attempt) {
    fail_after = attempt > 0 ? attempt : 0;
}

static int fail_allocation(void) {
    return fail_after > 0 && --fail_after == 0;
}

int wasmoon_native_allocation_allowed(void) {
    return !fail_allocation();
}

void *wasmoon_native_malloc(size_t size) {
    return fail_allocation() ? NULL : malloc(size);
}

void *wasmoon_native_calloc(size_t count, size_t size) {
    return fail_allocation() ? NULL : calloc(count, size);
}

void *wasmoon_native_realloc(void *pointer, size_t size) {
    return fail_allocation() ? NULL : realloc(pointer, size);
}
