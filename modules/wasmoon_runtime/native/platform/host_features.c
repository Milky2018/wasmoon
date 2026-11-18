// Copyright 2025
#include <moonbit.h>
#include <stdint.h>
#if defined(__aarch64__) && defined(__APPLE__)
#include <sys/sysctl.h>
#elif defined(__aarch64__) && defined(__linux__)
#include <asm/hwcap.h>
#include <sys/auxv.h>
#endif

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_host_target_arch(void) {
#if defined(__x86_64__) || defined(_M_X64)
    return 1;
#elif defined(__aarch64__) || defined(_M_ARM64)
    return 2;
#else
    return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_host_operating_system_abi(void) {
#if defined(__APPLE__)
    return 1;
#elif defined(__linux__) && defined(__GLIBC__)
    return 2;
#elif defined(__linux__)
    return 3;
#elif defined(_WIN32)
    return 4;
#else
    return 0;
#endif
}

MOONBIT_FFI_EXPORT int32_t wasmoon_jit_host_has_aarch64_lse(void) {
#if defined(__aarch64__) && defined(__APPLE__)
    int supported = 0;
    size_t size = sizeof(supported);
    return sysctlbyname("hw.optional.arm.FEAT_LSE", &supported, &size, NULL, 0) == 0
        && size == sizeof(supported) && supported != 0;
#elif defined(__aarch64__) && defined(__linux__) && defined(HWCAP_ATOMICS)
    return (getauxval(AT_HWCAP) & HWCAP_ATOMICS) != 0;
#else
    return 0;
#endif
}
