#include "moonbit.h"
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

MOONBIT_FFI_EXPORT int wasmoon_test_fs_is_windows(void) {
#ifdef _WIN32
  return 1;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t wasmoon_test_fs_temp_dir(void) {
#ifdef _WIN32
  DWORD capacity = GetTempPathW(0, NULL);
  if (!capacity) return moonbit_make_bytes(0, 0);
  wchar_t *wide = malloc(((size_t)capacity + 1) * sizeof(*wide));
  if (!wide) return moonbit_make_bytes(0, 0);
  DWORD length = GetTempPathW(capacity + 1, wide);
  if (!length || length > capacity) { free(wide); return moonbit_make_bytes(0, 0); }
  while (length > 3 && (wide[length - 1] == L'\\' || wide[length - 1] == L'/')) length--;
  for (DWORD i = 0; i < length; i++) if (wide[i] == L'\\') wide[i] = L'/';
  int bytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, (int)length, NULL, 0, NULL, NULL);
  moonbit_bytes_t result = moonbit_make_bytes(bytes, 0);
  if (bytes) WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, wide, (int)length, (char *)result, bytes, NULL, NULL);
  free(wide);
  return result;
#else
  moonbit_bytes_t result = moonbit_make_bytes(4, 0);
  memcpy(result, "/tmp", 4);
  return result;
#endif
}
