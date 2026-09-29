#include "registry.h"
#include "moonbit.h"
#include <stdlib.h>
#include <string.h>

static void clear_callable_registry(void *object) {
    jit_callable_registry_t *registry = object;
    free(registry->parents);
    free(registry->entries);
    registry->parents = NULL;
    registry->entries = NULL;
    registry->type_count = 0;
    registry->entry_count = 0;
}

MOONBIT_FFI_EXPORT void *wasmoon_callable_registry_new(void) {
    jit_callable_registry_t *registry = moonbit_make_external_object(
        clear_callable_registry, sizeof(*registry));
    *registry = (jit_callable_registry_t){0};
    return registry;
}

MOONBIT_FFI_EXPORT void wasmoon_callable_registry_clear(void *registry) {
    clear_callable_registry(registry);
}

static int compare_callable_entries(const void *left, const void *right) {
    const jit_callable_entry_t *a = left, *b = right;
    if (a->pointer != b->pointer) return a->pointer < b->pointer ? -1 : 1;
    return (a->ordinal > b->ordinal) - (a->ordinal < b->ordinal);
}

MOONBIT_FFI_EXPORT int32_t wasmoon_callable_registry_replace(
    void *object, const int32_t *parents, int32_t type_count,
    const int64_t *entries, int32_t entry_count
) {
    jit_callable_registry_t *registry = object;
    if (type_count < 0 || entry_count < 0 ||
        (type_count && !parents) || (entry_count && !entries)) return 0;
    int parents_changed = type_count != registry->type_count ||
        (type_count && memcmp(parents, registry->parents, (size_t)type_count * sizeof(int32_t)));
    int addresses_changed = entry_count != registry->entry_count;
    if (!addresses_changed) {
        for (int32_t i = 0; i < entry_count; ++i) {
            const jit_callable_entry_t *entry = &registry->entries[i];
            if (entry->pointer != (uint64_t)entries[(size_t)entry->ordinal * 2]) {
                addresses_changed = 1;
                break;
            }
        }
    }
    int32_t *parent_copy = parents_changed && type_count ? malloc((size_t)type_count * sizeof(int32_t)) : NULL;
    jit_callable_entry_t *entry_copy = addresses_changed && entry_count ?
        malloc((size_t)entry_count * sizeof(*entry_copy)) : NULL;
    if ((parents_changed && type_count && !parent_copy) ||
        (addresses_changed && entry_count && !entry_copy)) {
        free(parent_copy);
        free(entry_copy);
        return 0;
    }
    if (parent_copy) memcpy(parent_copy, parents, (size_t)type_count * sizeof(int32_t));
    if (entry_copy) {
        for (int32_t i = 0; i < entry_count; ++i) {
            entry_copy[i] = (jit_callable_entry_t){
                (uint64_t)entries[(size_t)i * 2], (int32_t)entries[(size_t)i * 2 + 1], i
            };
        }
        qsort(entry_copy, (size_t)entry_count, sizeof(*entry_copy), compare_callable_entries);
    }
    // Commit only after every fallible allocation has succeeded. Store execution
    // is serialized, so identity-only updates can reuse the existing sorted view.
    if (parents_changed) {
        free(registry->parents);
        registry->parents = parent_copy;
        registry->type_count = type_count;
    }
    if (addresses_changed) {
        free(registry->entries);
        registry->entries = entry_copy;
        registry->entry_count = entry_count;
    } else {
        for (int32_t i = 0; i < entry_count; ++i) {
            jit_callable_entry_t *entry = &registry->entries[i];
            entry->identity = (int32_t)entries[(size_t)entry->ordinal * 2 + 1];
        }
    }
    return 1;
}
