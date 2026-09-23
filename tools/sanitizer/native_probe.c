#include <stdlib.h>
#include "moonbit.h"

MOONBIT_FFI_EXPORT void wasmoon_sanitizer_native_probe(void) {
    volatile unsigned char *bytes = malloc(8);
    if (!bytes) abort();
    bytes[8] = 1;
    free((void *)bytes);
}
