#ifndef WASMOON_CALLABLE_REGISTRY_H
#define WASMOON_CALLABLE_REGISTRY_H
#include <stdint.h>

// Managed native object shared by all callable contexts belonging to one Store.
// It owns only metadata arrays, never contexts or executable code.
typedef struct {
    int32_t *parents;
    int64_t *entries;
    int32_t type_count;
    int32_t entry_count;
} jit_callable_registry_t;

#endif
