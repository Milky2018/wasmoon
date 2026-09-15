#ifndef WASMOON_WINDOWS_FS_H
#define WASMOON_WINDOWS_FS_H
#ifdef _WIN32
#include "windows_io.h"
#include <fcntl.h>
// Internal open tokens beyond the CRT flag range.
#define WASMOON_O_DIRECTORY 0x10000000
#define WASMOON_O_NOFOLLOW 0x20000000
#define WASMOON_O_NONBLOCK 0x04000000
int wasmoon_windows_error(DWORD error);
wchar_t *wasmoon_windows_utf16(const char *text);
int wasmoon_windows_open(const char *path, int flags, int mode);
int wasmoon_windows_openat(int fd, const char *name, int flags, int mode);
int wasmoon_windows_path_within_base(const char *base, const char *target);
unsigned char *wasmoon_windows_directory_entries(int fd, int *length);
int wasmoon_windows_is_symlink_at(int fd, const char *name);
int64_t wasmoon_windows_readlinkat(int fd, const char *name, char *buffer, size_t capacity);
#endif
#endif
