#include "quota.h"

static void finalize_quota(void *object) {
    (void)object;
}

MOONBIT_FFI_EXPORT wasmoon_quota_t *wasmoon_quota_new(int64_t limit) {
    wasmoon_quota_t *quota = moonbit_make_external_object(finalize_quota, sizeof(*quota));
    quota->limit = limit;
    atomic_init(&quota->used, 0);
    return quota;
}

// A native allocation can reserve units without invoking MoonBit or allocating.
MOONBIT_FFI_EXPORT int32_t wasmoon_quota_acquire(wasmoon_quota_t *quota, int64_t amount) {
    if (!quota) return 1;
    if (amount < 0) return 0;
    int64_t used = atomic_load_explicit(&quota->used, memory_order_relaxed);
    for (;;) {
        if (used > quota->limit || amount > quota->limit - used) return 0;
        if (atomic_compare_exchange_weak_explicit(&quota->used, &used, used + amount,
                                                memory_order_relaxed, memory_order_relaxed)) return 1;
    }
}

MOONBIT_FFI_EXPORT void wasmoon_quota_release(wasmoon_quota_t *quota, int64_t amount) {
    if (quota && amount > 0) atomic_fetch_sub_explicit(&quota->used, amount, memory_order_relaxed);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_quota_used(wasmoon_quota_t *quota) {
    return quota ? atomic_load_explicit(&quota->used, memory_order_relaxed) : 0;
}

MOONBIT_FFI_EXPORT void wasmoon_reservation_close(wasmoon_reservation_t *reservation) {
    wasmoon_quota_t *quota = reservation->quota;
    reservation->quota = NULL;
    if (quota) {
        wasmoon_quota_release(quota, reservation->amount);
        moonbit_decref(quota);
    }
    reservation->amount = 0;
}

static void finalize_reservation(void *object) {
    wasmoon_reservation_close(object);
}

MOONBIT_FFI_EXPORT wasmoon_reservation_t *wasmoon_reservation_new(wasmoon_quota_t *quota, int64_t amount) {
    wasmoon_reservation_t *reservation = moonbit_make_external_object(finalize_reservation, sizeof(*reservation));
    reservation->quota = NULL;
    reservation->amount = 0;
    if (quota && wasmoon_quota_acquire(quota, amount)) {
        moonbit_incref(quota);
        reservation->quota = quota;
        reservation->amount = amount;
    }
    return reservation;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_reservation_valid(wasmoon_reservation_t *reservation) {
    return reservation && reservation->quota;
}

// The resource owner serializes resizing (the memory growth lock for shared memory).
MOONBIT_FFI_EXPORT int32_t wasmoon_reservation_resize(wasmoon_reservation_t *reservation, int64_t amount) {
    if (!wasmoon_reservation_valid(reservation) || amount < 0) return 0;
    int64_t difference = amount - reservation->amount;
    if (difference > 0 && !wasmoon_quota_acquire(reservation->quota, difference)) return 0;
    if (difference < 0) wasmoon_quota_release(reservation->quota, -difference);
    reservation->amount = amount;
    return 1;
}

MOONBIT_FFI_EXPORT int32_t wasmoon_reservation_matches(wasmoon_reservation_t *reservation, wasmoon_quota_t *quota) {
    return reservation && reservation->quota == quota;
}
