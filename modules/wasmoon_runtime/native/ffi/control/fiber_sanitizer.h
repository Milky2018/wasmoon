#ifndef WASMOON_FIBER_SANITIZER_H
#define WASMOON_FIBER_SANITIZER_H

#include <stddef.h>

#if defined(__has_feature)
#if __has_feature(address_sanitizer)
#define WASMOON_ADDRESS_SANITIZER 1
#endif
#endif
#if !defined(WASMOON_ADDRESS_SANITIZER) && defined(__SANITIZE_ADDRESS__)
#define WASMOON_ADDRESS_SANITIZER 1
#endif

// Native stubs may be uninstrumented while generated MoonBit C links ASan.
// Discover that runtime as well, so stack-switch notifications stay active.
#if defined(WASMOON_ADDRESS_SANITIZER)
#include <sanitizer/common_interface_defs.h>
#define WASMOON_SANITIZER_FIBER_HOOKS 1
#define wasmoon_sanitizer_start_switch_fiber __sanitizer_start_switch_fiber
#define wasmoon_sanitizer_finish_switch_fiber __sanitizer_finish_switch_fiber
static inline int wasmoon_address_sanitizer_active(void) { return 1; }
#elif defined(__APPLE__)
#include <dlfcn.h>
#include <pthread.h>
#define WASMOON_SANITIZER_FIBER_HOOKS 1
static void (*wasmoon_sanitizer_start_switch_fiber)(void **, const void *, size_t);
static void (*wasmoon_sanitizer_finish_switch_fiber)(void *, const void **, size_t *);
static pthread_once_t wasmoon_sanitizer_once = PTHREAD_ONCE_INIT;
static void wasmoon_find_sanitizer(void) {
    void *process = dlopen(NULL, RTLD_LAZY);
    if (!process) return;
    wasmoon_sanitizer_start_switch_fiber = dlsym(process, "__sanitizer_start_switch_fiber");
    wasmoon_sanitizer_finish_switch_fiber = dlsym(process, "__sanitizer_finish_switch_fiber");
    dlclose(process);
}
static inline int wasmoon_address_sanitizer_active(void) {
    pthread_once(&wasmoon_sanitizer_once, wasmoon_find_sanitizer);
    return wasmoon_sanitizer_start_switch_fiber && wasmoon_sanitizer_finish_switch_fiber;
}
#elif !defined(_WIN32) && (defined(__GNUC__) || defined(__clang__))
extern void __asan_init(void) __attribute__((weak));
extern void __sanitizer_start_switch_fiber(void **, const void *, size_t) __attribute__((weak));
extern void __sanitizer_finish_switch_fiber(void *, const void **, size_t *) __attribute__((weak));
#define WASMOON_SANITIZER_FIBER_HOOKS 1
#define wasmoon_sanitizer_start_switch_fiber __sanitizer_start_switch_fiber
#define wasmoon_sanitizer_finish_switch_fiber __sanitizer_finish_switch_fiber
static inline int wasmoon_address_sanitizer_active(void) {
    return __asan_init != NULL;
}
#else
static inline int wasmoon_address_sanitizer_active(void) { return 0; }
#endif

#endif
