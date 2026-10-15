#ifndef WASMOON_NATIVE_ALLOC_H
#define WASMOON_NATIVE_ALLOC_H

#include <stddef.h>
#include <stdint.h>
#include <moonbit.h>

// Fallible native allocations and OS resource acquisition. The per-thread test
// hook rejects exactly one request; MoonBit-managed allocations are independent.
int wasmoon_native_allocation_allowed(void);
void *wasmoon_native_malloc(size_t size);
void *wasmoon_native_calloc(size_t count, size_t size);
void *wasmoon_native_realloc(void *pointer, size_t size);
MOONBIT_FFI_EXPORT void wasmoon_native_fail_allocation_for_tests(int32_t attempt);

#endif
