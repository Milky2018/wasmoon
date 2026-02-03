// Copyright 2026
// Host architecture detection for the vcode ISA layer.
//
// We use C preprocessor macros so the result reflects the actual compilation
// target (works on CI without requiring MoonBit conditional compilation).

#include "moonbit.h"

// Return codes:
//   0: AArch64
//   1: x86_64
//  -1: unknown/other
MOONBIT_FFI_EXPORT int wasmoon_host_arch(void) {
#if defined(__x86_64__) || defined(_M_X64)
  return 1;
#elif defined(__aarch64__) || defined(_M_ARM64)
  return 0;
#else
  return -1;
#endif
}

