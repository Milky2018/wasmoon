#ifndef WASMOON_QUOTA_H
#define WASMOON_QUOTA_H

#include <moonbit.h>
#include <stdint.h>
#include <stdatomic.h>

typedef struct {
    int64_t limit;
    _Atomic int64_t used;
} wasmoon_quota_t;

typedef struct {
    wasmoon_quota_t *quota;
    int64_t amount;
} wasmoon_reservation_t;

MOONBIT_FFI_EXPORT wasmoon_quota_t *wasmoon_quota_new(int64_t limit);
MOONBIT_FFI_EXPORT int32_t wasmoon_quota_acquire(wasmoon_quota_t *quota, int64_t amount);
MOONBIT_FFI_EXPORT void wasmoon_quota_release(wasmoon_quota_t *quota, int64_t amount);
MOONBIT_FFI_EXPORT int64_t wasmoon_quota_used(wasmoon_quota_t *quota);
MOONBIT_FFI_EXPORT wasmoon_reservation_t *wasmoon_reservation_new(wasmoon_quota_t *quota, int64_t amount);
MOONBIT_FFI_EXPORT int32_t wasmoon_reservation_valid(wasmoon_reservation_t *reservation);
MOONBIT_FFI_EXPORT int32_t wasmoon_reservation_resize(wasmoon_reservation_t *reservation, int64_t amount);
MOONBIT_FFI_EXPORT void wasmoon_reservation_close(wasmoon_reservation_t *reservation);
MOONBIT_FFI_EXPORT int32_t wasmoon_reservation_matches(wasmoon_reservation_t *reservation, wasmoon_quota_t *quota);

#endif
