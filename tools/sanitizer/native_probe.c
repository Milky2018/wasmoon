#include <stdlib.h>
#include "moonbit.h"

MOONBIT_FFI_EXPORT void wasmoon_sanitizer_native_probe(void) {
    volatile unsigned char *bytes = malloc(8);
    if (!bytes) abort();
    bytes[8] = 1;
    free((void *)bytes);
}

// Run only in the gate's separate Linux leak-detection positive control.
MOONBIT_FFI_EXPORT void wasmoon_sanitizer_leak_probe(void) {
    volatile unsigned char *bytes = malloc(17);
    if (!bytes) abort();
    bytes[0] = 1;
}
