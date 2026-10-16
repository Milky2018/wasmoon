#include <moonbit.h>
#include <stddef.h>
#include "ffi_callbacks.h"

typedef void (*cleanup_callback_t)(void *);

typedef struct {
    cleanup_callback_t callback;
    void *action;
} cleanup_owner_t;

// FuncRef fixes the ABI; the separately generated MoonBit closure struct has
// a nominal C tag erased at this native-stub boundary, as in other callbacks.
static WASMOON_NO_FUNCTION_SANITIZE void release_cleanup(void *object) {
    cleanup_owner_t *owner = object;
    void *action = owner->action;
    cleanup_callback_t callback = owner->callback;
    owner->action = NULL;
    owner->callback = NULL;
    // The generated FuncRef adapter borrows the closure during invocation.
    if (action) {
        callback(action);
        moonbit_decref(action);
    }
}

MOONBIT_FFI_EXPORT void *wasmoon_cleanup_owner_new(cleanup_callback_t callback, void *action) {
    cleanup_owner_t *owner = moonbit_make_external_object(release_cleanup, sizeof(*owner));
    owner->callback = callback;
    owner->action = action;
    return owner;
}

MOONBIT_FFI_EXPORT void wasmoon_cleanup_owner_close(void *owner) {
    release_cleanup(owner);
}
