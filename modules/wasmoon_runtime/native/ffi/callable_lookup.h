// Read-only callable views shared by the public C adapters and call boundary.
// Construction/publication remain owned by MoonBit NativeCallableRegistry.
#ifndef WASMOON_CALLABLE_LOOKUP_H
#define WASMOON_CALLABLE_LOOKUP_H

#include "jit_internal.h"

static inline int callable_subtype_registered(
    const jit_runtime_state_t *state, int32_t actual, int32_t local_expected
) {
    if ((uint32_t)local_expected >= (uint32_t)state->callable_local_type_count) return 0;
    int32_t expected = state->callable_local_types[local_expected];
    const jit_callable_registry_t *registry = state->callable_registry;
    if (!registry) return 0;
    // Counts are nonnegative at publication. Snapshot the read-only view once;
    // unsigned bounds checks also reject negative type indices.
    uint32_t type_count = (uint32_t)registry->type_count;
    const int32_t *parents = registry->parents;
    while ((uint32_t)actual < type_count) {
        if (actual == expected) return 1;
        int32_t parent = parents[actual];
        if (parent == actual) return 0;
        actual = parent;
    }
    return 0;
}

static inline int64_t callable_native_reference_inline(jit_context_t *ctx, int64_t value) {
    if ((value & STORE_FUNCREF_TAG) != STORE_FUNCREF_TAG || value < 0) return value;
    const jit_callable_registry_t *registry = ctx ? ctx_runtime(ctx)->callable_registry : NULL;
    if (!registry) return value;
    uint64_t address = (uint64_t)value & ~(uint64_t)STORE_FUNCREF_TAG;
    if (!address || address - 1 > INT32_MAX) return 0;
    uint64_t index = address - 1 - (uint32_t)registry->function_origin;
    if (registry->function_positions &&
        index < (uint32_t)Moonbit_array_length(registry->function_positions)) {
        int32_t position = registry->function_positions[index];
        return position ? registry->function_pointers[position - 1] | FUNCREF_TAG : value;
    }
    int32_t low = 0, high = registry->function_count;
    while (low < high) {
        int32_t mid = low + (high - low) / 2;
        if ((uint32_t)registry->function_stores[mid] < address - 1) low = mid + 1;
        else high = mid;
    }
    return low < registry->function_count && registry->function_stores[low] == (int32_t)(address - 1)
        ? registry->function_pointers[low] | FUNCREF_TAG : value;
}

static inline int32_t callable_type_for_value_inline(jit_context_t *ctx, int64_t value) {
    if (!ctx || !value) return -1;
    // The registry also indexes stable Store handles, including uncompiled
    // functions. Only legacy index values need executable-pointer conversion.
    uint64_t pointer;
    if (value >= 0 && (value & STORE_FUNCREF_TAG) == STORE_FUNCREF_TAG) {
        pointer = (uint64_t)value;
    } else if (value < 0) {
        int64_t index = -(value + 1);
        if (index < 0 || index >= ctx_func_count(ctx)) return -1;
        pointer = (uint64_t)(uintptr_t)ctx_func_table(ctx)[index];
    } else {
        pointer = (uint64_t)value & ~FUNCREF_TAG;
    }
    const jit_callable_registry_t *registry = ctx_runtime(ctx)->callable_registry;
    if (!registry) return -1;
    if (value >= 0 && (value & STORE_FUNCREF_TAG) == STORE_FUNCREF_TAG && registry->store_positions) {
        uint64_t index = ((uint64_t)value & ~(uint64_t)STORE_FUNCREF_TAG) - 1 -
            (uint32_t)registry->store_origin;
        if (index < (uint32_t)Moonbit_array_length(registry->store_positions)) {
            int32_t position = registry->store_positions[index];
            return position ? registry->identities[position - 1] : -1;
        }
    }
    int32_t low = 0, high = registry->entry_count;
    while (low < high) {
        int32_t middle = low + (high - low) / 2;
        if ((uint64_t)registry->addresses[middle] < pointer)
            low = middle + 1;
        else
            high = middle;
    }
    if (low < registry->entry_count && (uint64_t)registry->addresses[low] == pointer)
        return registry->identities[low];
    return -1;
}

#endif
