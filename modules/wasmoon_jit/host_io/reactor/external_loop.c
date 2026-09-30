#include "moonbit.h"
#include <errno.h>

MOONBIT_FFI_EXPORT int wasmoon_async_reactor_wake(void *object);

/* The main thread owns this reference from installation until the async
   waiter has joined. The foreign-thread callback never touches MoonBit RC. */
static void *external_reactor;

MOONBIT_FFI_EXPORT int wasmoon_async_external_loop_attach(void *reactor) {
  if (external_reactor) {
    moonbit_decref(reactor);
    return EBUSY;
  }
  external_reactor = reactor;
  return 0;
}

MOONBIT_FFI_EXPORT void wasmoon_async_external_loop_wake(void) {
  if (external_reactor) (void)wasmoon_async_reactor_wake(external_reactor);
}

MOONBIT_FFI_EXPORT void wasmoon_async_external_loop_detach(void) {
  void *reactor = external_reactor;
  external_reactor = NULL;
  if (reactor) moonbit_decref(reactor);
}
