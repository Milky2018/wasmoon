#include "registry.h"
#include "moonbit.h"

static void release_callable_view(void *object) {
    jit_callable_registry_t *view = object;
    if (view->parents) moonbit_decref(view->parents);
    if (view->addresses) moonbit_decref(view->addresses);
    if (view->identities) moonbit_decref(view->identities);
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
    release_callable_view(view);
    *view = (jit_callable_registry_t){
        parents, addresses, identities, type_count, entry_count
    };
}
