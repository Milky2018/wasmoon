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
#include <direct.h>
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
#include <dirent.h>
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

// Create a directory
MOONBIT_FFI_EXPORT int wasmoon_wasi_mkdir(moonbit_bytes_t path, int mode) {
#ifdef _WIN32
  (void)mode;  // Windows mkdir doesn't use mode
  return _mkdir((const char *)path);
#else
  return mkdir((const char *)path, mode);
#endif
}

// Directory entry structure for readdir
// Returns a serialized format: count (4 bytes) + entries
// Each entry: is_dir (1 byte) + name_len (4 bytes) + name (variable)
MOONBIT_FFI_EXPORT moonbit_bytes_t wasmoon_wasi_readdir(moonbit_bytes_t path) {
#ifdef _WIN32
  // Windows implementation using FindFirstFile/FindNextFile
  // For now, return empty result on Windows
  moonbit_bytes_t result = moonbit_make_bytes(4, 0);
  memset(result, 0, 4);  // count = 0
  return result;
#else
  DIR *dir = opendir((const char *)path);
  if (!dir) {
    return NULL;
  }

  // First pass: count entries and calculate total size
  int count = 0;
  size_t total_size = 4;  // 4 bytes for count
  struct dirent *entry;

  while ((entry = readdir(dir)) != NULL) {
    // Skip . and ..
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    count++;
    total_size += 1 + 4 + strlen(entry->d_name);  // is_dir + name_len + name
  }

  // Allocate result buffer
  moonbit_bytes_t result = moonbit_make_bytes(total_size, 0);

  // Write count (little-endian)
  result[0] = count & 0xFF;
  result[1] = (count >> 8) & 0xFF;
  result[2] = (count >> 16) & 0xFF;
  result[3] = (count >> 24) & 0xFF;

  // Second pass: write entries
  rewinddir(dir);
  size_t offset = 4;

  while ((entry = readdir(dir)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }

    // Determine if it's a directory
    int is_dir = (entry->d_type == DT_DIR) ? 1 : 0;
    result[offset] = is_dir;
    offset++;

    // Write name length (little-endian)
    size_t name_len = strlen(entry->d_name);
    result[offset] = name_len & 0xFF;
    result[offset + 1] = (name_len >> 8) & 0xFF;
    result[offset + 2] = (name_len >> 16) & 0xFF;
    result[offset + 3] = (name_len >> 24) & 0xFF;
    offset += 4;

    // Write name
    memcpy(result + offset, entry->d_name, name_len);
    offset += name_len;
  }

  closedir(dir);
  return result;
#endif
}

// Print string to stdout without newline
MOONBIT_FFI_EXPORT void wasmoon_print_string(moonbit_bytes_t str, int len) {
  fwrite(str, 1, len, stdout);
  fflush(stdout);
}

#ifdef __cplusplus
}
#endif
