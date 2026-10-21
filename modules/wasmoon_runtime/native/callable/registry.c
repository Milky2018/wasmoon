#include "registry.h"
#include "moonbit.h"

static void release_callable_view(void *object) {
    jit_callable_registry_t *view = object;
    if (view->parents) moonbit_decref(view->parents);
    if (view->addresses) moonbit_decref(view->addresses);
    if (view->identities) moonbit_decref(view->identities);
    if (view->function_stores) moonbit_decref(view->function_stores);
    if (view->function_pointers) moonbit_decref(view->function_pointers);
    if (view->reference_pointers) moonbit_decref(view->reference_pointers);
    if (view->reference_stores) moonbit_decref(view->reference_stores);
}

MOONBIT_FFI_EXPORT void *wasmoon_callable_view_new(void) {
    jit_callable_registry_t *view = moonbit_make_external_object(
        release_callable_view, sizeof(*view));
    *view = (jit_callable_registry_t){0};
    return view;
}

MOONBIT_FFI_EXPORT void wasmoon_callable_view_publish(
    void *object, int32_t *parents, int32_t type_count,
    int64_t *addresses, int32_t *identities, int32_t entry_count
) {
    jit_callable_registry_t *view = object;
    // Retain before release: unchanged arrays may be republished in the same view.
    moonbit_incref(parents);
    moonbit_incref(addresses);
    moonbit_incref(identities);
    if (view->parents) moonbit_decref(view->parents);
    if (view->addresses) moonbit_decref(view->addresses);
    if (view->identities) moonbit_decref(view->identities);
    view->parents = parents;
    view->addresses = addresses;
    view->identities = identities;
    view->type_count = type_count;
    view->entry_count = entry_count;
}

MOONBIT_FFI_EXPORT void wasmoon_callable_view_publish_functions(
    void *object, int32_t *stores, int64_t *pointers, int32_t count,
    int64_t *references, int32_t *reference_stores, int32_t reference_count
) {
    jit_callable_registry_t *view = object;
    moonbit_incref(stores);
    moonbit_incref(pointers);
    moonbit_incref(references);
    moonbit_incref(reference_stores);
    if (view->function_stores) moonbit_decref(view->function_stores);
    if (view->function_pointers) moonbit_decref(view->function_pointers);
    if (view->reference_pointers) moonbit_decref(view->reference_pointers);
    if (view->reference_stores) moonbit_decref(view->reference_stores);
    view->function_stores = stores;
    view->function_pointers = pointers;
    view->function_count = count;
    view->reference_pointers = references;
    view->reference_stores = reference_stores;
    view->reference_count = reference_count;
}
