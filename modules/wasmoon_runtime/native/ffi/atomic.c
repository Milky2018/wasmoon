// Sequentially consistent operations on checked linear-memory addresses.
#include "jit_internal.h"

static void *atomic_address(wasmoon_memory_t *descriptor, int64_t offset) {
    wasmoon_memory_t *memory = descriptor;
    return memory->base + (uint64_t)offset;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_memory_atomic_load(
    wasmoon_memory_t *descriptor, int64_t offset, int32_t width
) {
    void *address = atomic_address(descriptor, offset);
#define LOAD_CASE(WIDTH, TYPE) case WIDTH: return (int64_t)atomic_load_explicit((_Atomic(TYPE) *)address, memory_order_seq_cst)
    switch (width) {
        LOAD_CASE(1, uint8_t);
        LOAD_CASE(2, uint16_t);
        LOAD_CASE(4, uint32_t);
        LOAD_CASE(8, uint64_t);
        default: abort();
    }
#undef LOAD_CASE
}

MOONBIT_FFI_EXPORT void wasmoon_memory_atomic_store(
    wasmoon_memory_t *descriptor, int64_t offset, int32_t width, int64_t value
) {
    void *address = atomic_address(descriptor, offset);
#define STORE_CASE(WIDTH, TYPE) case WIDTH: atomic_store_explicit((_Atomic(TYPE) *)address, (TYPE)value, memory_order_seq_cst); return
    switch (width) {
        STORE_CASE(1, uint8_t);
        STORE_CASE(2, uint16_t);
        STORE_CASE(4, uint32_t);
        STORE_CASE(8, uint64_t);
        default: abort();
    }
#undef STORE_CASE
}

MOONBIT_FFI_EXPORT int64_t wasmoon_memory_atomic_rmw(
    wasmoon_memory_t *descriptor, int64_t offset, int32_t width, int32_t operation, int64_t value
) {
    void *address = atomic_address(descriptor, offset);
#define RMW_CASE(WIDTH, TYPE) case WIDTH: { \
    _Atomic(TYPE) *pointer = (_Atomic(TYPE) *)address; \
    TYPE operand = (TYPE)value; \
    switch (operation) { \
        case 0: return (int64_t)atomic_fetch_add_explicit(pointer, operand, memory_order_seq_cst); \
        case 1: return (int64_t)atomic_fetch_sub_explicit(pointer, operand, memory_order_seq_cst); \
        case 2: return (int64_t)atomic_fetch_and_explicit(pointer, operand, memory_order_seq_cst); \
        case 3: return (int64_t)atomic_fetch_or_explicit(pointer, operand, memory_order_seq_cst); \
        case 4: return (int64_t)atomic_fetch_xor_explicit(pointer, operand, memory_order_seq_cst); \
        case 5: return (int64_t)atomic_exchange_explicit(pointer, operand, memory_order_seq_cst); \
        default: abort(); \
    } \
}
    switch (width) {
        RMW_CASE(1, uint8_t);
        RMW_CASE(2, uint16_t);
        RMW_CASE(4, uint32_t);
        RMW_CASE(8, uint64_t);
        default: abort();
    }
#undef RMW_CASE
}

MOONBIT_FFI_EXPORT int64_t wasmoon_memory_atomic_compare_exchange(
    wasmoon_memory_t *descriptor, int64_t offset, int32_t width, int64_t expected, int64_t replacement
) {
    void *address = atomic_address(descriptor, offset);
#define CAS_CASE(WIDTH, TYPE) case WIDTH: { \
    TYPE old = (TYPE)expected; \
    atomic_compare_exchange_strong_explicit((_Atomic(TYPE) *)address, &old, (TYPE)replacement, memory_order_seq_cst, memory_order_seq_cst); \
    return (int64_t)old; \
}
    switch (width) {
        CAS_CASE(1, uint8_t);
        CAS_CASE(2, uint16_t);
        CAS_CASE(4, uint32_t);
        CAS_CASE(8, uint64_t);
        default: abort();
    }
#undef CAS_CASE
}

MOONBIT_FFI_EXPORT void wasmoon_atomic_fence(void) {
    atomic_thread_fence(memory_order_seq_cst);
}
