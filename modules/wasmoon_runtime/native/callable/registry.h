#ifndef WASMOON_CALLABLE_REGISTRY_H
#define WASMOON_CALLABLE_REGISTRY_H

#include <stdint.h>

// Read-only native view. Each pointer is an RC-owned MoonBit FixedArray payload.
// MoonBit owns ordering, identity updates and publication policy.
// Optional bounded Store indices contain record ordinals, not cached targets.
// Replacing keys republishes their index; identity/pointer reads stay current.
typedef struct {
    int32_t *parents;
    int64_t *addresses;
    int32_t *identities;
    int32_t type_count;
    int32_t entry_count;
    int32_t *function_stores;
    int64_t *function_pointers;
    int32_t function_count;
    int64_t *reference_pointers;
    int32_t *reference_stores;
    int32_t reference_count;
    int32_t store_origin;
    int32_t *store_positions;
    int32_t function_origin;
    int32_t *function_positions;
} jit_callable_registry_t;

#endif
