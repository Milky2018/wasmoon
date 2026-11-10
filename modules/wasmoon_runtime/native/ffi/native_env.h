#ifndef WASMOON_NATIVE_ENV_H
#define WASMOON_NATIVE_ENV_H

#include <string.h>

static inline int wasmoon_native_env_truthy(const char *value) {
    if (!value) return 0;
    return strcmp(value, "1") == 0 ||
           strcmp(value, "true") == 0 ||
           strcmp(value, "TRUE") == 0 ||
           strcmp(value, "yes") == 0 ||
           strcmp(value, "YES") == 0 ||
           strcmp(value, "on") == 0 ||
           strcmp(value, "ON") == 0;
}

#endif
