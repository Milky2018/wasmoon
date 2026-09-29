#ifndef WASMOON_CALLABLE_REGISTRY_H
#define WASMOON_CALLABLE_REGISTRY_H

#include <stdint.h>

typedef struct {
    uint64_t pointer;
    int32_t identity;
    // Original input position preserves first-match semantics for duplicates.
    int32_t ordinal;
} jit_callable_entry_t;

typedef struct {
    int32_t *parents;
    jit_callable_entry_t *entries;
    int32_t type_count;
    int32_t entry_count;
} jit_callable_registry_t;

_Static_assert(sizeof(jit_callable_entry_t) == 16, "callable entry size");

#endif
