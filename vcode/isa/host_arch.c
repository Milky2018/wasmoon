// Copyright 2026
// Host architecture detection for the vcode ISA layer.
//
// We use C preprocessor macros so the result reflects the actual compilation
// target (works on CI without requiring MoonBit conditional compilation).

#include "moonbit.h"

#if !defined(_WIN32)
#include <string.h>
#include <sys/utsname.h>
#endif

// Return codes:
//   0: AArch64
//   1: amd64
//  -1: unknown/other
MOONBIT_FFI_EXPORT int wasmoon_host_arch(void) {
  // Prefer compile-time target macros: they reflect the instruction set of the
  // *current process*, even if running under emulation.
#if defined(__x86_64__) || defined(__x86_64) || defined(__amd64__) || defined(__amd64) || \
  defined(_M_X64)
  return 1;
#elif defined(__aarch64__) || defined(__arm64__) || defined(__ARM64__) || defined(_M_ARM64)
  return 0;
#else
#if !defined(_WIN32)
  // Fallback: runtime detection. Note that uname() may reflect the *kernel*
  // architecture (e.g. when running under user-mode emulation), so we only
  // use it if the compiler didn't provide a target macro.
  struct utsname u;
  if (uname(&u) == 0) {
    if (strcmp(u.machine, "x86_64") == 0 || strcmp(u.machine, "amd64") == 0) {
      return 1;
    }
    if (strcmp(u.machine, "aarch64") == 0 || strcmp(u.machine, "arm64") == 0) {
      return 0;
    }
  }
#endif
  return -1;
#endif
}
