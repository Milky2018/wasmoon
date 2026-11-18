#ifndef WASMOON_ATOMIC_WAIT_H
#define WASMOON_ATOMIC_WAIT_H

#include "../context/jit_ffi.h"

MOONBIT_FFI_EXPORT void *wasmoon_atomic_wait_begin(wasmoon_memory_t *, int64_t, int32_t, int64_t, int64_t);
MOONBIT_FFI_EXPORT int32_t wasmoon_atomic_wait_poll(void *);
MOONBIT_FFI_EXPORT void wasmoon_atomic_wait_destroy(void *);
MOONBIT_FFI_EXPORT int32_t wasmoon_atomic_notify(wasmoon_memory_t *, int64_t, int32_t);
int32_t wasmoon_atomic_wait_guest(jit_context_t *, wasmoon_memory_t *, int64_t, int32_t, int64_t, int64_t);

#endif
