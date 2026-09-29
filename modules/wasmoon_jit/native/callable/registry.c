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

MOONBIT_FFI_EXPORT int32_t wasmoon_callable_registry_replace(
    void *object, const int32_t *parents, int32_t type_count,
    const int64_t *entries, int32_t entry_count
) {
    jit_callable_registry_t *registry = object;
    if (type_count < 0 || entry_count < 0 ||
        (type_count && !parents) || (entry_count && !entries)) return 0;
    int32_t *parent_copy = type_count ? malloc((size_t)type_count * sizeof(int32_t)) : NULL;
    int64_t *entry_copy = entry_count ? malloc((size_t)entry_count * 2 * sizeof(int64_t)) : NULL;
    if ((type_count && !parent_copy) || (entry_count && !entry_copy)) {
        free(parent_copy);
        free(entry_copy);
        return 0;
    }
    if (type_count) memcpy(parent_copy, parents, (size_t)type_count * sizeof(int32_t));
    if (entry_count) memcpy(entry_copy, entries, (size_t)entry_count * 2 * sizeof(int64_t));
    // Publish only after both copies succeed. Store execution is serialized.
    clear_callable_registry(registry);
    registry->parents = parent_copy;
    registry->type_count = type_count;
    registry->entries = entry_copy;
    registry->entry_count = entry_count;
    return 1;
}

