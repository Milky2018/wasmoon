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
#include <stdlib.h>
#if defined(__linux__) && defined(__GLIBC__) && (__GLIBC__ > 2 || (__GLIBC__ == 2 && __GLIBC_MINOR__ >= 25))
#include <sys/random.h>
#endif
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

// Print a single character to stdout
MOONBIT_FFI_EXPORT void wasmoon_putchar(int c) {
  putchar(c);
  fflush(stdout);
}

// ============================================================================
// Phase 1: Core file operations
// ============================================================================

// Sync file to disk
MOONBIT_FFI_EXPORT int wasmoon_wasi_fsync(int fd) {
#ifdef _WIN32
  return _commit(fd);
#else
  return fsync(fd);
#endif
}

// Sync file data (not metadata) to disk
MOONBIT_FFI_EXPORT int wasmoon_wasi_fdatasync(int fd) {
#ifdef _WIN32
  return _commit(fd);
#elif defined(__APPLE__)
  // macOS doesn't have fdatasync, use fsync
  return fsync(fd);
#else
  return fdatasync(fd);
#endif
}

// Unlink file or directory (with AT_REMOVEDIR flag)
MOONBIT_FFI_EXPORT int wasmoon_wasi_unlinkat(int dirfd, moonbit_bytes_t path, int flags) {
#ifdef _WIN32
  (void)dirfd;
  (void)flags;
  // Windows: simple unlink for files, rmdir for directories
  if (flags & 0x200) {  // AT_REMOVEDIR
    return _rmdir((const char *)path);
  } else {
    return _unlink((const char *)path);
  }
#else
  return unlinkat(dirfd, (const char *)path, flags);
#endif
}

// Rename file or directory
MOONBIT_FFI_EXPORT int wasmoon_wasi_renameat(int old_dirfd, moonbit_bytes_t old_path,
                                              int new_dirfd, moonbit_bytes_t new_path) {
#ifdef _WIN32
  (void)old_dirfd;
  (void)new_dirfd;
  return rename((const char *)old_path, (const char *)new_path);
#else
  return renameat(old_dirfd, (const char *)old_path, new_dirfd, (const char *)new_path);
#endif
}

// ============================================================================
// Phase 2: File metadata operations
// ============================================================================

// Get file stat via fd
MOONBIT_FFI_EXPORT int wasmoon_wasi_fstat(int fd,
    uint64_t *dev, uint64_t *ino, uint8_t *filetype,
    uint64_t *nlink, uint64_t *size,
    uint64_t *atim, uint64_t *mtim, uint64_t *ctim) {
  struct stat st;
#ifdef _WIN32
  if (_fstat64(fd, (struct __stat64 *)&st) != 0) {
    return -1;
  }
#else
  if (fstat(fd, &st) != 0) {
    return -1;
  }
#endif
  *dev = st.st_dev;
  *ino = st.st_ino;
  *nlink = st.st_nlink;
  *size = st.st_size;

  // Determine file type
  if (S_ISDIR(st.st_mode)) {
    *filetype = 3;  // directory
  } else if (S_ISREG(st.st_mode)) {
    *filetype = 4;  // regular_file
  } else if (S_ISLNK(st.st_mode)) {
    *filetype = 7;  // symbolic_link
  } else if (S_ISCHR(st.st_mode)) {
    *filetype = 2;  // character_device
  } else if (S_ISBLK(st.st_mode)) {
    *filetype = 1;  // block_device
  } else {
    *filetype = 0;  // unknown
  }

  // Convert timespec to nanoseconds
#ifdef _WIN32
  *atim = (uint64_t)st.st_atime * 1000000000ULL;
  *mtim = (uint64_t)st.st_mtime * 1000000000ULL;
  *ctim = (uint64_t)st.st_ctime * 1000000000ULL;
#elif defined(__APPLE__)
  *atim = (uint64_t)st.st_atimespec.tv_sec * 1000000000ULL + st.st_atimespec.tv_nsec;
  *mtim = (uint64_t)st.st_mtimespec.tv_sec * 1000000000ULL + st.st_mtimespec.tv_nsec;
  *ctim = (uint64_t)st.st_ctimespec.tv_sec * 1000000000ULL + st.st_ctimespec.tv_nsec;
#else
  *atim = (uint64_t)st.st_atim.tv_sec * 1000000000ULL + st.st_atim.tv_nsec;
  *mtim = (uint64_t)st.st_mtim.tv_sec * 1000000000ULL + st.st_mtim.tv_nsec;
  *ctim = (uint64_t)st.st_ctim.tv_sec * 1000000000ULL + st.st_ctim.tv_nsec;
#endif
  return 0;
}

// Get file stat via path (relative to dirfd)
MOONBIT_FFI_EXPORT int wasmoon_wasi_fstatat(int dirfd, moonbit_bytes_t path, int flags,
    uint64_t *dev, uint64_t *ino, uint8_t *filetype,
    uint64_t *nlink, uint64_t *size,
    uint64_t *atim, uint64_t *mtim, uint64_t *ctim) {
  struct stat st;
#ifdef _WIN32
  (void)dirfd;
  (void)flags;
  if (_stat64((const char *)path, (struct __stat64 *)&st) != 0) {
    return -1;
  }
#else
  if (fstatat(dirfd, (const char *)path, &st, flags) != 0) {
    return -1;
  }
#endif
  *dev = st.st_dev;
  *ino = st.st_ino;
  *nlink = st.st_nlink;
  *size = st.st_size;

  // Determine file type
  if (S_ISDIR(st.st_mode)) {
    *filetype = 3;  // directory
  } else if (S_ISREG(st.st_mode)) {
    *filetype = 4;  // regular_file
  } else if (S_ISLNK(st.st_mode)) {
    *filetype = 7;  // symbolic_link
  } else if (S_ISCHR(st.st_mode)) {
    *filetype = 2;  // character_device
  } else if (S_ISBLK(st.st_mode)) {
    *filetype = 1;  // block_device
  } else {
    *filetype = 0;  // unknown
  }

  // Convert timespec to nanoseconds
#ifdef _WIN32
  *atim = (uint64_t)st.st_atime * 1000000000ULL;
  *mtim = (uint64_t)st.st_mtime * 1000000000ULL;
  *ctim = (uint64_t)st.st_ctime * 1000000000ULL;
#elif defined(__APPLE__)
  *atim = (uint64_t)st.st_atimespec.tv_sec * 1000000000ULL + st.st_atimespec.tv_nsec;
  *mtim = (uint64_t)st.st_mtimespec.tv_sec * 1000000000ULL + st.st_mtimespec.tv_nsec;
  *ctim = (uint64_t)st.st_ctimespec.tv_sec * 1000000000ULL + st.st_ctimespec.tv_nsec;
#else
  *atim = (uint64_t)st.st_atim.tv_sec * 1000000000ULL + st.st_atim.tv_nsec;
  *mtim = (uint64_t)st.st_mtim.tv_sec * 1000000000ULL + st.st_mtim.tv_nsec;
  *ctim = (uint64_t)st.st_ctim.tv_sec * 1000000000ULL + st.st_ctim.tv_nsec;
#endif
  return 0;
}

// Truncate file to specified size
MOONBIT_FFI_EXPORT int wasmoon_wasi_ftruncate(int fd, int64_t size) {
#ifdef _WIN32
  return _chsize_s(fd, size);
#else
  return ftruncate(fd, size);
#endif
}

// Set file times
MOONBIT_FFI_EXPORT int wasmoon_wasi_futimens(int fd, int64_t atim, int64_t mtim, int fst_flags) {
#ifdef _WIN32
  (void)fd;
  (void)atim;
  (void)mtim;
  (void)fst_flags;
  // Not easily supported on Windows
  return -1;
#else
  struct timespec times[2];

  // fst_flags bits:
  // 0x01 = SET_ATIM (use atim)
  // 0x02 = SET_ATIM_NOW (use current time)
  // 0x04 = SET_MTIM (use mtim)
  // 0x08 = SET_MTIM_NOW (use current time)

  if (fst_flags & 0x02) {
    times[0].tv_nsec = UTIME_NOW;
    times[0].tv_sec = 0;
  } else if (fst_flags & 0x01) {
    times[0].tv_sec = atim / 1000000000LL;
    times[0].tv_nsec = atim % 1000000000LL;
  } else {
    times[0].tv_nsec = UTIME_OMIT;
    times[0].tv_sec = 0;
  }

  if (fst_flags & 0x08) {
    times[1].tv_nsec = UTIME_NOW;
    times[1].tv_sec = 0;
  } else if (fst_flags & 0x04) {
    times[1].tv_sec = mtim / 1000000000LL;
    times[1].tv_nsec = mtim % 1000000000LL;
  } else {
    times[1].tv_nsec = UTIME_OMIT;
    times[1].tv_sec = 0;
  }

  return futimens(fd, times);
#endif
}

// Set file times via path
MOONBIT_FFI_EXPORT int wasmoon_wasi_utimensat(int dirfd, moonbit_bytes_t path,
    int64_t atim, int64_t mtim, int fst_flags, int lookup_flags) {
#ifdef _WIN32
  (void)dirfd;
  (void)path;
  (void)atim;
  (void)mtim;
  (void)fst_flags;
  (void)lookup_flags;
  return -1;
#else
  struct timespec times[2];

  if (fst_flags & 0x02) {
    times[0].tv_nsec = UTIME_NOW;
    times[0].tv_sec = 0;
  } else if (fst_flags & 0x01) {
    times[0].tv_sec = atim / 1000000000LL;
    times[0].tv_nsec = atim % 1000000000LL;
  } else {
    times[0].tv_nsec = UTIME_OMIT;
    times[0].tv_sec = 0;
  }

  if (fst_flags & 0x08) {
    times[1].tv_nsec = UTIME_NOW;
    times[1].tv_sec = 0;
  } else if (fst_flags & 0x04) {
    times[1].tv_sec = mtim / 1000000000LL;
    times[1].tv_nsec = mtim % 1000000000LL;
  } else {
    times[1].tv_nsec = UTIME_OMIT;
    times[1].tv_sec = 0;
  }

  return utimensat(dirfd, (const char *)path, times, lookup_flags);
#endif
}

// ============================================================================
// Phase 3: Auxiliary functions
// ============================================================================

// Set fd flags
MOONBIT_FFI_EXPORT int wasmoon_wasi_fcntl_setfl(int fd, int flags) {
#ifdef _WIN32
  (void)fd;
  (void)flags;
  return -1;  // Not supported on Windows
#else
  return fcntl(fd, F_SETFL, flags);
#endif
}

// Get fd flags
MOONBIT_FFI_EXPORT int wasmoon_wasi_fcntl_getfl(int fd) {
#ifdef _WIN32
  (void)fd;
  return -1;  // Not supported on Windows
#else
  return fcntl(fd, F_GETFL);
#endif
}

// Duplicate fd to specific number
MOONBIT_FFI_EXPORT int wasmoon_wasi_dup2(int oldfd, int newfd) {
#ifdef _WIN32
  return _dup2(oldfd, newfd);
#else
  return dup2(oldfd, newfd);
#endif
}

// ============================================================================
// Phase 4: Symlink operations
// ============================================================================

// Create symbolic link
MOONBIT_FFI_EXPORT int wasmoon_wasi_symlinkat(moonbit_bytes_t target, int dirfd, moonbit_bytes_t linkpath) {
#ifdef _WIN32
  (void)target;
  (void)dirfd;
  (void)linkpath;
  return -1;  // Symlinks require admin on Windows
#else
  return symlinkat((const char *)target, dirfd, (const char *)linkpath);
#endif
}

// Read symbolic link
MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_readlinkat(int dirfd, moonbit_bytes_t path,
    moonbit_bytes_t buf, int64_t bufsize) {
#ifdef _WIN32
  (void)dirfd;
  (void)path;
  (void)buf;
  (void)bufsize;
  return -1;
#else
  return readlinkat(dirfd, (const char *)path, (char *)buf, bufsize);
#endif
}

// Create hard link
MOONBIT_FFI_EXPORT int wasmoon_wasi_linkat(int olddirfd, moonbit_bytes_t oldpath,
    int newdirfd, moonbit_bytes_t newpath, int flags) {
#ifdef _WIN32
  (void)olddirfd;
  (void)newdirfd;
  (void)flags;
  // Windows: CreateHardLink only works with absolute paths
  return -1;
#else
  return linkat(olddirfd, (const char *)oldpath, newdirfd, (const char *)newpath, flags);
#endif
}

// ============================================================================
// Phase 5: Poll and socket operations
// ============================================================================

#ifndef _WIN32
#include <poll.h>
#include <sys/socket.h>
#include <signal.h>
#include <time.h>
#endif

// Nanosleep - sleep for specified nanoseconds
// Returns 0 on success, -1 on error
MOONBIT_FFI_EXPORT int wasmoon_wasi_nanosleep(int64_t ns) {
#ifdef _WIN32
  // Windows: use Sleep (milliseconds)
  Sleep((DWORD)(ns / 1000000));
  return 0;
#else
  struct timespec req;
  req.tv_sec = ns / 1000000000LL;
  req.tv_nsec = ns % 1000000000LL;
  return nanosleep(&req, NULL);
#endif
}

// Get current time in nanoseconds (monotonic clock)
MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_clock_gettime_monotonic(void) {
#ifdef _WIN32
  // Windows: use QueryPerformanceCounter
  LARGE_INTEGER freq, count;
  QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&count);
  return (int64_t)((double)count.QuadPart / freq.QuadPart * 1000000000.0);
#else
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
}

// Get current time in nanoseconds (realtime clock)
MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_clock_gettime_realtime(void) {
#ifdef _WIN32
  FILETIME ft;
  GetSystemTimeAsFileTime(&ft);
  // Convert to nanoseconds since Unix epoch
  uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
  t -= 116444736000000000ULL; // Windows epoch to Unix epoch
  return t * 100;  // 100ns units to ns
#else
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
}

// Poll on file descriptors
// fds_ptr: array of (fd, events) pairs
// nfds: number of fds
// timeout_ms: timeout in milliseconds (-1 for infinite)
// Returns number of ready fds, or -1 on error
MOONBIT_FFI_EXPORT int wasmoon_wasi_poll(int* fds_ptr, int16_t* events_ptr,
    int16_t* revents_ptr, int nfds, int timeout_ms) {
#ifdef _WIN32
  (void)fds_ptr;
  (void)events_ptr;
  (void)revents_ptr;
  (void)nfds;
  (void)timeout_ms;
  return -1;  // Not easily supported on Windows
#else
  if (nfds <= 0 || nfds > 256) return -1;

  struct pollfd pfds[256];
  for (int i = 0; i < nfds; i++) {
    pfds[i].fd = fds_ptr[i];
    pfds[i].events = events_ptr[i];
    pfds[i].revents = 0;
  }

  int result = poll(pfds, nfds, timeout_ms);

  for (int i = 0; i < nfds; i++) {
    revents_ptr[i] = pfds[i].revents;
  }

  return result;
#endif
}

// Socket recv
MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_recv(int sockfd, moonbit_bytes_t buf,
    int64_t len, int flags) {
#ifdef _WIN32
  (void)sockfd;
  (void)buf;
  (void)len;
  (void)flags;
  return -1;
#else
  return recv(sockfd, buf, len, flags);
#endif
}

// Socket send
MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_send(int sockfd, moonbit_bytes_t buf,
    int64_t len, int flags) {
#ifdef _WIN32
  (void)sockfd;
  (void)buf;
  (void)len;
  (void)flags;
  return -1;
#else
  return send(sockfd, buf, len, flags);
#endif
}

// Socket shutdown
MOONBIT_FFI_EXPORT int wasmoon_wasi_shutdown(int sockfd, int how) {
#ifdef _WIN32
  (void)sockfd;
  (void)how;
  return -1;
#else
  return shutdown(sockfd, how);
#endif
}

// Socket accept
MOONBIT_FFI_EXPORT int wasmoon_wasi_accept(int sockfd) {
#ifdef _WIN32
  (void)sockfd;
  return -1;
#else
  return accept(sockfd, NULL, NULL);
#endif
}

// Raise a signal
MOONBIT_FFI_EXPORT int wasmoon_wasi_raise(int sig) {
#ifdef _WIN32
  return raise(sig);
#else
  return raise(sig);
#endif
}

// Get random bytes from system
// Returns 0 on success, -1 on error
MOONBIT_FFI_EXPORT int wasmoon_wasi_getrandom(uint8_t* buf, size_t len) {
#ifdef _WIN32
  // Windows: use RtlGenRandom (SystemFunction036)
  // Available on Windows XP and later
  extern BOOLEAN NTAPI SystemFunction036(PVOID, ULONG);
  if (SystemFunction036(buf, (ULONG)len)) {
    return 0;
  }
  return -1;
#elif defined(__APPLE__)
  // macOS: use arc4random_buf (always available, never fails)
  arc4random_buf(buf, len);
  return 0;
#elif defined(__linux__)
  // Linux: use getrandom if available, fallback to /dev/urandom
  #if defined(__GLIBC__) && (__GLIBC__ > 2 || (__GLIBC__ == 2 && __GLIBC_MINOR__ >= 25))
    ssize_t ret = getrandom(buf, len, 0);
    return (ret == (ssize_t)len) ? 0 : -1;
  #else
    // Fallback to /dev/urandom
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) return -1;
    ssize_t ret = read(fd, buf, len);
    close(fd);
    return (ret == (ssize_t)len) ? 0 : -1;
  #endif
#else
  // Other Unix: use /dev/urandom
  int fd = open("/dev/urandom", O_RDONLY);
  if (fd < 0) return -1;
  ssize_t ret = read(fd, buf, len);
  close(fd);
  return (ret == (ssize_t)len) ? 0 : -1;
#endif
}

#ifdef __cplusplus
}
#endif
