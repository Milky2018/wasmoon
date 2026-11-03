#include "registry.h"
#include "moonbit.h"

// The existing dense executable index owns these slots. Small maps leave
// enough bits above the original ordinal for an exact type or a miss marker.
static void refresh_direct_slots(jit_callable_registry_t *view) {
    int32_t span = view->function_positions
        ? Moonbit_array_length(view->function_positions) : 0;
    int32_t store_span = view->store_positions
        ? Moonbit_array_length(view->store_positions) : 0;
    view->direct_span = 0;
    if (!store_span || span > 16384 || view->function_count > UINT16_MAX)
        return;
    for (int32_t i = 0; i < span; ++i) {
        uint32_t ordinal = (uint32_t)view->function_positions[i] & UINT16_MAX;
        uint32_t identity = 0x7fff;
        uint64_t address = (uint64_t)(uint32_t)view->function_origin + (uint32_t)i;
        uint64_t relative = address - (uint32_t)view->store_origin;
        if (ordinal && ordinal <= (uint32_t)view->function_count &&
            relative < (uint32_t)store_span) {
            int32_t position = view->store_positions[relative];
            if (position > 0 && position <= view->entry_count) {
                uint32_t candidate = (uint32_t)view->identities[position - 1];
                if (candidate < (uint32_t)view->type_count && candidate < 0x7fff)
                    identity = candidate;
            }
        }
        view->function_positions[i] = (int32_t)((identity << 16) | ordinal);
    }
    view->direct_span = span;
}

static void release_callable_view(void *object) {
    jit_callable_registry_t *view = object;
    if (view->parents) moonbit_decref(view->parents);
    if (view->addresses) moonbit_decref(view->addresses);
    if (view->identities) moonbit_decref(view->identities);
    if (view->function_stores) moonbit_decref(view->function_stores);
    if (view->function_pointers) moonbit_decref(view->function_pointers);
    if (view->reference_pointers) moonbit_decref(view->reference_pointers);
    if (view->reference_stores) moonbit_decref(view->reference_stores);
    if (view->store_positions) moonbit_decref(view->store_positions);
    if (view->function_positions) moonbit_decref(view->function_positions);
}

MOONBIT_FFI_EXPORT void *wasmoon_callable_view_new(void) {
    jit_callable_registry_t *view = moonbit_make_external_object(
        release_callable_view, sizeof(*view));
    *view = (jit_callable_registry_t){0};
    return view;
}

MOONBIT_FFI_EXPORT void wasmoon_callable_view_publish(
    void *object, int32_t *parents, int32_t type_count,
    int64_t *addresses, int32_t *identities, int32_t entry_count,
    int32_t store_origin, int32_t *store_positions
) {
    jit_callable_registry_t *view = object;
    // Retain before release: unchanged arrays may be republished in the same view.
    moonbit_incref(parents);
    moonbit_incref(addresses);
    moonbit_incref(identities);
    moonbit_incref(store_positions);
    if (view->parents) moonbit_decref(view->parents);
    if (view->addresses) moonbit_decref(view->addresses);
    if (view->identities) moonbit_decref(view->identities);
    if (view->store_positions) moonbit_decref(view->store_positions);
    view->parents = parents;
    view->addresses = addresses;
    view->identities = identities;
    view->type_count = type_count;
    view->entry_count = entry_count;
    view->store_origin = store_origin;
    view->store_positions = store_positions;
    refresh_direct_slots(view);
}

MOONBIT_FFI_EXPORT void wasmoon_callable_view_publish_functions(
    void *object, int32_t *stores, int64_t *pointers, int32_t count,
    int64_t *references, int32_t *reference_stores, int32_t reference_count,
    int32_t store_origin, int32_t *store_positions
) {
    jit_callable_registry_t *view = object;
    moonbit_incref(stores);
    moonbit_incref(pointers);
    moonbit_incref(references);
    moonbit_incref(reference_stores);
    moonbit_incref(store_positions);
    if (view->function_stores) moonbit_decref(view->function_stores);
    if (view->function_pointers) moonbit_decref(view->function_pointers);
    if (view->reference_pointers) moonbit_decref(view->reference_pointers);
    if (view->reference_stores) moonbit_decref(view->reference_stores);
    if (view->function_positions) moonbit_decref(view->function_positions);
    view->function_stores = stores;
    view->function_pointers = pointers;
    view->function_count = count;
    view->reference_pointers = references;
    view->reference_stores = reference_stores;
    view->reference_count = reference_count;
    view->function_origin = store_origin;
    view->function_positions = store_positions;
    refresh_direct_slots(view);
}
