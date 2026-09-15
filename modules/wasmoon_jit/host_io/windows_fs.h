#ifndef WASMOON_WINDOWS_FS_H
#define WASMOON_WINDOWS_FS_H
#ifdef _WIN32
#include "windows_io.h"
#include <fcntl.h>
// Internal open tokens beyond the CRT flag range.
#define WASMOON_O_DIRECTORY 0x10000000
#define WASMOON_O_NOFOLLOW 0x20000000
#define WASMOON_O_NONBLOCK 0x04000000
wchar_t *wasmoon_windows_utf16(const char *text);
int wasmoon_windows_open(const char *path, int flags, int mode);
int wasmoon_windows_openat(int fd, const char *name, int flags, int mode);
typedef struct {
  uint64_t st_dev, st_ino, st_nlink, st_size;
  uint64_t atim_ns, mtim_ns, ctim_ns;
  uint8_t filetype;
} wasmoon_windows_stat;
int wasmoon_windows_fstat(int fd, wasmoon_windows_stat *stat);
int wasmoon_windows_fstatat(int fd, const char *path, int follow, wasmoon_windows_stat *stat);
int wasmoon_windows_mkdirat(int fd, const char *path);
int wasmoon_windows_unlinkat(int fd, const char *path, int directory);
int wasmoon_windows_renameat(int old_fd, const char *old_path, int new_fd, const char *new_path);
int wasmoon_windows_linkat(int old_fd, const char *old_path, int new_fd, const char *new_path, int follow);
int wasmoon_windows_futimens(int fd, int64_t atim, int64_t mtim, int flags);
int wasmoon_windows_utimensat(int fd, const char *path, int64_t atim, int64_t mtim, int flags, int follow);
int wasmoon_windows_path_within_base(const char *base, const char *target);
unsigned char *wasmoon_windows_directory_entries(int fd, int *length);
int wasmoon_windows_is_symlink_at(int fd, const char *name);
int64_t wasmoon_windows_readlinkat(int fd, const char *name, char *buffer, size_t capacity);
#endif
#endif
