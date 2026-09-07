// Copyright 2026
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"
#ifndef _WIN32
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include "native_filetype.h"
#endif

#ifndef _WIN32
static uint8_t wasmoon_wasi_dirent_filetype(
  DIR *dir,
  const struct dirent *entry
) {
#ifdef AT_SYMLINK_NOFOLLOW
  struct stat st;
  if (fstatat(dirfd(dir), entry->d_name, &st, AT_SYMLINK_NOFOLLOW) == 0) {
    return wasmoon_wasi_filetype_from_mode(st.st_mode);
  }
#endif

  switch (entry->d_type) {
#ifdef DT_BLK
    case DT_BLK: return 1;
#endif
#ifdef DT_CHR
    case DT_CHR: return 2;
#endif
#ifdef DT_DIR
    case DT_DIR: return 3;
#endif
#ifdef DT_REG
    case DT_REG: return 4;
#endif
#ifdef DT_SOCK
    case DT_SOCK: return 6;
#endif
#ifdef DT_LNK
    case DT_LNK: return 7;
#endif
#ifdef DT_FIFO
    case DT_FIFO: return 8;
#endif
    default: return 0;
  }
}
#endif

#ifndef _WIN32
// Own the stream and serialize each entry once. Directory contents can change
// while being read, so counting and then rewinding cannot size a safe buffer.
static moonbit_bytes_t serialize_directory(DIR *dir) {
  size_t capacity = 256;
  size_t used = 4;
  uint32_t count = 0;
  unsigned char *buffer = malloc(capacity);
  if (!buffer) {
    closedir(dir);
    errno = ENOMEM;
    return NULL;
  }
  int error = 0;
  for (;;) {
    errno = 0;
    struct dirent *entry = readdir(dir);
    if (!entry) {
      error = errno;
      break;
    }
    if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
    size_t name_len = strlen(entry->d_name);
    size_t required = used + 5 + name_len;
    if (required > INT32_MAX) {
      error = EOVERFLOW;
      break;
    }
    if (required > capacity) {
      size_t next = capacity <= INT32_MAX / 2 ? capacity * 2 : INT32_MAX;
      if (next < required) next = required;
      unsigned char *grown = realloc(buffer, next);
      if (!grown) {
        error = ENOMEM;
        break;
      }
      buffer = grown;
      capacity = next;
    }
    buffer[used++] = wasmoon_wasi_dirent_filetype(dir, entry);
    for (int i = 0; i < 4; i++) buffer[used++] = (name_len >> (i * 8)) & 0xff;
    memcpy(buffer + used, entry->d_name, name_len);
    used += name_len;
    count++;
  }
  if (closedir(dir) != 0 && !error) error = errno;
  moonbit_bytes_t result = NULL;
  if (!error) {
    for (int i = 0; i < 4; i++) buffer[i] = (count >> (i * 8)) & 0xff;
    result = moonbit_make_bytes((int32_t)used, 0);
    memcpy(result, buffer, used);
  }
  free(buffer);
  errno = error;
  return result;
}
#endif

// Wire format: count:u32le followed by type:u8, name_len:u32le and name bytes.
MOONBIT_FFI_EXPORT moonbit_bytes_t wasmoon_wasi_readdir(moonbit_bytes_t path) {
#ifdef _WIN32
  (void)path;
  return moonbit_make_bytes(4, 0);
#else
  DIR *dir = opendir((const char *)path);
  return dir ? serialize_directory(dir) : NULL;
#endif
}

MOONBIT_FFI_EXPORT moonbit_bytes_t wasmoon_wasi_readdir_fd(int fd) {
#ifdef _WIN32
  (void)fd;
  return moonbit_make_bytes(4, 0);
#else
  // dup shares the directory offset. Reopen relative to the descriptor instead
  // of a stored path, keeping each scan independent even after a rename.
  int scan_fd = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
  if (scan_fd < 0) return NULL;
  DIR *dir = fdopendir(scan_fd);
  if (!dir) {
    int error = errno;
    close(scan_fd);
    errno = error;
    return NULL;
  }
  return serialize_directory(dir);
#endif
}
