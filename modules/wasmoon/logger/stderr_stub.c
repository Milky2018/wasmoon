// Standard error output for the logger.
//
// MoonBit's core library has no stderr facility, so diagnostics would
// otherwise share stdout with program output (ISS-376).

#ifdef __cplusplus
extern "C" {
#endif

#include <stdio.h>

#include "moonbit.h"

MOONBIT_FFI_EXPORT int wasmoon_logger_write_stderr(moonbit_bytes_t buf,
                                                   int count) {
  if (count <= 0) {
    return 0;
  }
  size_t written = fwrite(buf, 1, (size_t)count, stderr);
  fflush(stderr);
  return (int)written;
}

#ifdef __cplusplus
}
#endif
