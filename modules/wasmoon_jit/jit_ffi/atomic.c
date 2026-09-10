// Sequentially consistent operations on checked linear-memory addresses.
#include "jit_internal.h"

static void *atomic_address(int64_t descriptor, int64_t offset) {
    wasmoon_memory_t *memory = (wasmoon_memory_t *)(uintptr_t)descriptor;
    return memory->base + (uint64_t)offset;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_memory_atomic_load(
    int64_t descriptor, int64_t offset, int32_t width
) {
    void *address = atomic_address(descriptor, offset);
#define LOAD_CASE(WIDTH, TYPE) case WIDTH: return (int64_t)__atomic_load_n((TYPE *)address, __ATOMIC_SEQ_CST)
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
    int64_t descriptor, int64_t offset, int32_t width, int64_t value
) {
    void *address = atomic_address(descriptor, offset);
#define STORE_CASE(WIDTH, TYPE) case WIDTH: __atomic_store_n((TYPE *)address, (TYPE)value, __ATOMIC_SEQ_CST); return
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
    int64_t descriptor, int64_t offset, int32_t width, int32_t operation, int64_t value
) {
    void *address = atomic_address(descriptor, offset);
#define RMW_CASE(WIDTH, TYPE) case WIDTH: { \
    TYPE *pointer = (TYPE *)address; \
    TYPE operand = (TYPE)value; \
    switch (operation) { \
        case 0: return (int64_t)__atomic_fetch_add(pointer, operand, __ATOMIC_SEQ_CST); \
        case 1: return (int64_t)__atomic_fetch_sub(pointer, operand, __ATOMIC_SEQ_CST); \
        case 2: return (int64_t)__atomic_fetch_and(pointer, operand, __ATOMIC_SEQ_CST); \
        case 3: return (int64_t)__atomic_fetch_or(pointer, operand, __ATOMIC_SEQ_CST); \
        case 4: return (int64_t)__atomic_fetch_xor(pointer, operand, __ATOMIC_SEQ_CST); \
        case 5: return (int64_t)__atomic_exchange_n(pointer, operand, __ATOMIC_SEQ_CST); \
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
    int64_t descriptor, int64_t offset, int32_t width, int64_t expected, int64_t replacement
) {
    void *address = atomic_address(descriptor, offset);
#define CAS_CASE(WIDTH, TYPE) case WIDTH: { \
    TYPE old = (TYPE)expected; \
    __atomic_compare_exchange_n((TYPE *)address, &old, (TYPE)replacement, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST); \
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
    __atomic_thread_fence(__ATOMIC_SEQ_CST);
}
