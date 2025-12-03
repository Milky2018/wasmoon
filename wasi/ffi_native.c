// Copyright 2025
// WASI file system FFI implementation

#ifdef __cplusplus
extern "C" {
#endif

#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <io.h>
#include <fcntl.h>
#define O_RDONLY _O_RDONLY
#define O_WRONLY _O_WRONLY
#define O_RDWR _O_RDWR
#define O_CREAT _O_CREAT
#define O_TRUNC _O_TRUNC
#define O_APPEND _O_APPEND
#define O_EXCL _O_EXCL
#else
#include <fcntl.h>
#include <unistd.h>
#endif

#include "moonbit.h"

// Open a file and return file descriptor
MOONBIT_FFI_EXPORT int wasmoon_wasi_open(moonbit_bytes_t path, int flags, int mode) {
#ifdef _WIN32
  return _open((const char *)path, flags, mode);
#else
  return open((const char *)path, flags, mode);
#endif
}

// Close a file descriptor
MOONBIT_FFI_EXPORT int wasmoon_wasi_close(int fd) {
#ifdef _WIN32
  return _close(fd);
#else
  return close(fd);
#endif
}

// Read from file descriptor
MOONBIT_FFI_EXPORT int wasmoon_wasi_read(int fd, moonbit_bytes_t buf, int count) {
#ifdef _WIN32
  return _read(fd, buf, count);
#else
  return read(fd, buf, count);
#endif
}

// Write to file descriptor
MOONBIT_FFI_EXPORT int wasmoon_wasi_write(int fd, moonbit_bytes_t buf, int count) {
#ifdef _WIN32
  return _write(fd, buf, count);
#else
  return write(fd, buf, count);
#endif
}

// Seek in file
MOONBIT_FFI_EXPORT long long wasmoon_wasi_lseek(int fd, long long offset, int whence) {
#ifdef _WIN32
  return _lseeki64(fd, offset, whence);
#else
  return lseek(fd, offset, whence);
#endif
}

// Get error message
MOONBIT_FFI_EXPORT moonbit_bytes_t wasmoon_wasi_get_error_message(void) {
  const char *err_str = strerror(errno);
  size_t len = strlen(err_str);
  moonbit_bytes_t bytes = moonbit_make_bytes(len, 0);
  memcpy(bytes, err_str, len);
  return bytes;
}

// Get errno value
MOONBIT_FFI_EXPORT int wasmoon_wasi_get_errno(void) {
  return errno;
}

// Platform-specific open flags
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_rdonly(void) { return O_RDONLY; }
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_wronly(void) { return O_WRONLY; }
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_rdwr(void) { return O_RDWR; }
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_creat(void) { return O_CREAT; }
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_trunc(void) { return O_TRUNC; }
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_append(void) { return O_APPEND; }
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_excl(void) { return O_EXCL; }

#ifdef __cplusplus
}
#endif
