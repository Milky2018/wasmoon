#include <moonbit.h>

#ifdef _WIN32

#include <windows.h>

MOONBIT_FFI_EXPORT int64_t perf_instant_now_ffi() {
  LARGE_INTEGER t;
  QueryPerformanceCounter(&t);
  return t.QuadPart;
}

MOONBIT_FFI_EXPORT double perf_instant_as_secs_f64_ffi(int64_t t) {
  LARGE_INTEGER freq;
  QueryPerformanceFrequency(&freq);
  return ((double)t) / ((double)freq.QuadPart);
}

#else

#include <time.h>

MOONBIT_FFI_EXPORT int64_t perf_instant_now_ffi() {
  struct timespec value;
  clock_gettime(CLOCK_MONOTONIC, &value);
  return ((int64_t)value.tv_sec * 1000000000ll) + (int64_t)value.tv_nsec;
}

MOONBIT_FFI_EXPORT double perf_instant_as_secs_f64_ffi(int64_t t) {
  return ((double)t) * 1e-9;
}

#endif
