// Copyright 2025
// WASI file system FFI implementation

#ifdef __cplusplus
extern "C" {
#endif

#include <errno.h>
#include <limits.h>
#include <stdint.h>
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

// Native file-type tokens shared with the MoonBit side. Values 0-7 match
// WASI Preview 1 filetype; 8 extends the internal protocol for FIFO, which is
// represented explicitly by the Component Model.
static uint8_t wasmoon_wasi_filetype_from_mode(mode_t mode) {
  if (S_ISDIR(mode)) return 3;
  if (S_ISREG(mode)) return 4;
  if (S_ISLNK(mode)) return 7;
  if (S_ISCHR(mode)) return 2;
  if (S_ISBLK(mode)) return 1;
#ifdef S_ISSOCK
  if (S_ISSOCK(mode)) return 6;
#endif
#ifdef S_ISFIFO
  if (S_ISFIFO(mode)) return 8;
#endif
  return 0;
}

// Internal token values used by MoonBit side. Translate to host constants
// before calling libc APIs so behavior is consistent across platforms.
#define WASMOON_AT_REMOVEDIR_TOKEN 0x200
#define WASMOON_AT_SYMLINK_NOFOLLOW_TOKEN 0x100

#ifndef _WIN32
static int wasmoon_wasi_path_is_within_base(
  const char *base_real,
  const char *target_real
);

static void wasmoon_wasi_close_fd_stack(int *fds, size_t length) {
  for (size_t i = 0; i < length; i++) close(fds[i]);
}

static int wasmoon_wasi_push_fd(int **fds, size_t *length, size_t *capacity, int fd) {
  if (*length == *capacity) {
    if (*capacity > SIZE_MAX / 2 / sizeof(int)) {
      errno = ENOMEM;
      return 0;
    }
    size_t next_capacity = *capacity == 0 ? 8 : *capacity * 2;
    int *next = (int *)realloc(*fds, next_capacity * sizeof(int));
    if (!next) {
      errno = ENOMEM;
      return 0;
    }
    *fds = next;
    *capacity = next_capacity;
  }
  (*fds)[*length] = fd;
  *length += 1;
  return 1;
}

static int wasmoon_wasi_path_has_component(const char *path) {
  while (*path == '/') path++;
  return *path != '\0';
}

static int wasmoon_wasi_is_symlink_at(int dir_fd, const char *name) {
  struct stat stat_buffer;
  return fstatat(dir_fd, name, &stat_buffer, AT_SYMLINK_NOFOLLOW) == 0 &&
         S_ISLNK(stat_buffer.st_mode);
}

static char *wasmoon_wasi_prepend_symlink_target(
  const char *target,
  const char *remaining
) {
  size_t target_length = strlen(target);
  while (*remaining == '/') remaining++;
  size_t remaining_length = strlen(remaining);
  size_t separator_length = remaining_length == 0 ? 0 : 1;
  if (target_length > SIZE_MAX - remaining_length) {
    errno = ENAMETOOLONG;
    return NULL;
  }
  size_t combined_length = target_length + remaining_length;
  if (combined_length > SIZE_MAX - separator_length - 1) {
    errno = ENAMETOOLONG;
    return NULL;
  }
  char *result = (char *)malloc(
    target_length + separator_length + remaining_length + 1
  );
  if (!result) {
    errno = ENOMEM;
    return NULL;
  }
  memcpy(result, target, target_length);
  if (separator_length != 0) result[target_length] = '/';
  memcpy(
    result + target_length + separator_length,
    remaining,
    remaining_length + 1
  );
  return result;
}

// Resolve from the capability root one component at a time. Keeping every
// descended directory open makes ".." a stack operation and prevents rename
// races from turning it into ambient parent traversal.
static int wasmoon_wasi_open_beneath_impl(
  int root_fd,
  const char *path,
  int flags,
  int mode,
  int follow_final
) {
  if (!path || path[0] == '/') {
    errno = EPERM;
    return -1;
  }
#ifndef O_NOFOLLOW
  (void)root_fd;
  (void)flags;
  (void)mode;
  (void)follow_final;
  errno = ENOTSUP;
  return -1;
#else
  int *fds = NULL;
  size_t fd_length = 0;
  size_t fd_capacity = 0;
  int root_copy = dup(root_fd);
  if (root_copy < 0) return -1;
  if (!wasmoon_wasi_push_fd(&fds, &fd_length, &fd_capacity, root_copy)) {
    int saved_errno = errno;
    close(root_copy);
    free(fds);
    errno = saved_errno;
    return -1;
  }

  char *work = strdup(path);
  if (!work) {
    wasmoon_wasi_close_fd_stack(fds, fd_length);
    free(fds);
    errno = ENOMEM;
    return -1;
  }
  char *cursor = work;
  int symlink_count = 0;

  for (;;) {
    while (*cursor == '/') cursor++;
    if (*cursor == '\0') {
      int open_flags = flags | O_CLOEXEC | O_NOFOLLOW;
      int wants_truncate = (open_flags & O_TRUNC) != 0;
      open_flags &= ~O_TRUNC;
      int result = openat(fds[fd_length - 1], ".", open_flags, mode);
      if (result >= 0 && wants_truncate && ftruncate(result, 0) != 0) {
        int saved_errno = errno;
        close(result);
        errno = saved_errno;
        result = -1;
      }
      int saved_errno = errno;
      free(work);
      wasmoon_wasi_close_fd_stack(fds, fd_length);
      free(fds);
      errno = saved_errno;
      return result;
    }

    char *separator = strchr(cursor, '/');
    char *remaining = separator ? separator + 1 : cursor + strlen(cursor);
    if (separator) *separator = '\0';
    const char *component = cursor;
    int is_final = !wasmoon_wasi_path_has_component(remaining);

    if (strcmp(component, ".") == 0) {
      cursor = remaining;
      continue;
    }
    if (strcmp(component, "..") == 0) {
      if (fd_length == 1) {
        errno = EPERM;
        goto fail;
      }
      close(fds[fd_length - 1]);
      fd_length -= 1;
      cursor = remaining;
      continue;
    }

    int open_flags;
    int wants_truncate = 0;
    if (is_final) {
      open_flags = flags | O_CLOEXEC | O_NOFOLLOW;
      wants_truncate = (open_flags & O_TRUNC) != 0;
      open_flags &= ~O_TRUNC;
    } else {
      open_flags = O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW;
    }
    int opened = openat(fds[fd_length - 1], component, open_flags, mode);
    if (opened >= 0) {
      if (is_final) {
        if (wants_truncate && ftruncate(opened, 0) != 0) {
          int saved_errno = errno;
          close(opened);
          errno = saved_errno;
          goto fail;
        }
        free(work);
        wasmoon_wasi_close_fd_stack(fds, fd_length);
        free(fds);
        return opened;
      }
      if (!wasmoon_wasi_push_fd(&fds, &fd_length, &fd_capacity, opened)) {
        int saved_errno = errno;
        close(opened);
        errno = saved_errno;
        goto fail;
      }
      cursor = remaining;
      continue;
    }

    int open_errno = errno;
    if (!wasmoon_wasi_is_symlink_at(fds[fd_length - 1], component)) {
      errno = open_errno;
      goto fail;
    }
    if (is_final &&
        (!follow_final || ((flags & O_CREAT) != 0 && (flags & O_EXCL) != 0))) {
      errno = open_errno;
      goto fail;
    }
    symlink_count += 1;
    if (symlink_count > 40) {
      errno = ELOOP;
      goto fail;
    }
    char target[PATH_MAX + 1];
    ssize_t target_length = readlinkat(
      fds[fd_length - 1],
      component,
      target,
      PATH_MAX
    );
    if (target_length < 0) goto fail;
    if (target_length == 0) {
      errno = ENOENT;
      goto fail;
    }
    if (target_length >= PATH_MAX) {
      errno = ENAMETOOLONG;
      goto fail;
    }
    target[target_length] = '\0';
    if (target[0] == '/') {
      errno = EPERM;
      goto fail;
    }
    char *next_work = wasmoon_wasi_prepend_symlink_target(target, remaining);
    if (!next_work) goto fail;
    free(work);
    work = next_work;
    cursor = work;
  }

fail: {
    int saved_errno = errno;
    free(work);
    wasmoon_wasi_close_fd_stack(fds, fd_length);
    free(fds);
    errno = saved_errno;
    return -1;
  }
#endif
}

static int wasmoon_wasi_open_parent_beneath_impl(int root_fd, const char *path) {
  return wasmoon_wasi_open_beneath_impl(
    root_fd,
    path,
    O_RDONLY | O_DIRECTORY,
    0,
    1
  );
}

static int wasmoon_wasi_path_is_within_base(const char *base_real, const char *target_real) {
  if (!base_real || !target_real) return 0;
  if (strcmp(base_real, "/") == 0) {
    return target_real[0] == '/';
  }
  size_t base_len = strlen(base_real);
  if (strncmp(base_real, target_real, base_len) != 0) return 0;
  char next = target_real[base_len];
  return next == '\0' || next == '/';
}

static int wasmoon_wasi_realpath_existing_parent(const char *path, char **out_real) {
  if (!path || !out_real) return 0;
  *out_real = NULL;

  char *scratch = strdup(path);
  if (!scratch) return 0;

  while (1) {
    errno = 0;
    char *resolved = realpath(scratch, NULL);
    if (resolved) {
      *out_real = resolved;
      free(scratch);
      return 1;
    }

    if (errno != ENOENT && errno != ENOTDIR) {
      break;
    }

    char *slash = strrchr(scratch, '/');
    if (!slash) {
      scratch[0] = '.';
      scratch[1] = '\0';
    } else if (slash == scratch) {
      scratch[1] = '\0';
    } else {
      *slash = '\0';
    }
  }

  free(scratch);
  return 0;
}

static int wasmoon_wasi_path_within_base_impl(const char *base_path, const char *target_path) {
  if (!base_path || !target_path) return 0;

  char *base_real = realpath(base_path, NULL);
  if (!base_real) return 0;

  char *target_real = realpath(target_path, NULL);
  if (!target_real) {
    if (!wasmoon_wasi_realpath_existing_parent(target_path, &target_real)) {
      free(base_real);
      return 0;
    }
  }

  int ok = wasmoon_wasi_path_is_within_base(base_real, target_real);
  free(base_real);
  free(target_real);
  return ok;
}
#endif

// Open a file and return file descriptor
MOONBIT_FFI_EXPORT int wasmoon_wasi_open(moonbit_bytes_t path, int flags, int mode) {
#ifdef _WIN32
  return _open((const char *)path, flags, mode);
#else
  return open((const char *)path, flags, mode);
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_open_parent_beneath(
  int root_fd,
  moonbit_bytes_t path
) {
#ifdef _WIN32
  (void)root_fd;
  (void)path;
  errno = ENOTSUP;
  return -1;
#else
  return wasmoon_wasi_open_parent_beneath_impl(root_fd, (const char *)path);
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_openat_beneath(
  int root_fd,
  moonbit_bytes_t parent_path,
  moonbit_bytes_t leaf,
  int flags,
  int mode,
  int follow_final
) {
#ifdef _WIN32
  (void)root_fd;
  (void)parent_path;
  (void)leaf;
  (void)flags;
  (void)mode;
  (void)follow_final;
  errno = ENOTSUP;
  return -1;
#else
  const char *parent = (const char *)parent_path;
  const char *name = (const char *)leaf;
  if (name[0] == '\0' || strchr(name, '/') != NULL) {
    errno = EINVAL;
    return -1;
  }
  size_t parent_length = strlen(parent);
  size_t name_length = strlen(name);
  size_t separator_length = parent_length == 0 ? 0 : 1;
  if (parent_length > SIZE_MAX - name_length) {
    errno = ENAMETOOLONG;
    return -1;
  }
  size_t combined_length = parent_length + name_length;
  if (combined_length > SIZE_MAX - separator_length - 1) {
    errno = ENAMETOOLONG;
    return -1;
  }
  char *path = (char *)malloc(
    parent_length + separator_length + name_length + 1
  );
  if (!path) {
    errno = ENOMEM;
    return -1;
  }
  memcpy(path, parent, parent_length);
  if (separator_length != 0) path[parent_length] = '/';
  memcpy(path + parent_length + separator_length, name, name_length + 1);
  int result = wasmoon_wasi_open_beneath_impl(
    root_fd,
    path,
    flags,
    mode,
    follow_final
  );
  free(path);
  return result;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_dup(int fd) {
#ifdef _WIN32
  return _dup(fd);
#else
  return dup(fd);
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

MOONBIT_FFI_EXPORT int wasmoon_wasi_pread(
  int fd,
  moonbit_bytes_t buf,
  int count,
  int64_t offset
) {
#ifdef _WIN32
  int64_t saved = _lseeki64(fd, 0, SEEK_CUR);
  if (saved < 0 || _lseeki64(fd, offset, SEEK_SET) < 0) return -1;
  int result = _read(fd, buf, count);
  int saved_errno = errno;
  _lseeki64(fd, saved, SEEK_SET);
  errno = saved_errno;
  return result;
#else
  return pread(fd, buf, count, (off_t)offset);
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_pwrite(
  int fd,
  moonbit_bytes_t buf,
  int count,
  int64_t offset
) {
#ifdef _WIN32
  int64_t saved = _lseeki64(fd, 0, SEEK_CUR);
  if (saved < 0 || _lseeki64(fd, offset, SEEK_SET) < 0) return -1;
  int result = _write(fd, buf, count);
  int saved_errno = errno;
  _lseeki64(fd, saved, SEEK_SET);
  errno = saved_errno;
  return result;
#else
  return pwrite(fd, buf, count, (off_t)offset);
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

MOONBIT_FFI_EXPORT int wasmoon_wasi_isatty(int fd) {
#ifdef _WIN32
  return _isatty(fd);
#else
  return isatty(fd);
#endif
}

// Check whether a target path stays within the base directory after canonical
// resolution (including symlink traversal).
MOONBIT_FFI_EXPORT int wasmoon_wasi_path_within_base(
  moonbit_bytes_t base_path,
  moonbit_bytes_t target_path
) {
#ifdef _WIN32
  (void)base_path;
  (void)target_path;
  return 1;
#else
  return wasmoon_wasi_path_within_base_impl(
    (const char *)base_path,
    (const char *)target_path
  );
#endif
}

// Convert native errno value to WASI preview1 errno number.
MOONBIT_FFI_EXPORT int wasmoon_wasi_errno_to_wasi(int err) {
  switch (err) {
    case 0: return 0;   // ESUCCESS
#ifdef E2BIG
    case E2BIG: return 1;
#endif
#ifdef EACCES
    case EACCES: return 2;
#endif
#ifdef EAGAIN
    case EAGAIN: return 6;
#endif
#if defined(EWOULDBLOCK) && (!defined(EAGAIN) || EWOULDBLOCK != EAGAIN)
    case EWOULDBLOCK: return 6;
#endif
#ifdef EALREADY
    case EALREADY: return 7;
#endif
#ifdef EBADF
    case EBADF: return 8;
#endif
#ifdef EBUSY
    case EBUSY: return 10;
#endif
#ifdef ECANCELED
    case ECANCELED: return 11;
#endif
#ifdef ECHILD
    case ECHILD: return 12;
#endif
#ifdef ECONNABORTED
    case ECONNABORTED: return 13;
#endif
#ifdef ECONNREFUSED
    case ECONNREFUSED: return 14;
#endif
#ifdef ECONNRESET
    case ECONNRESET: return 15;
#endif
#if defined(EDEADLK)
    case EDEADLK: return 16;
#endif
#if defined(EDEADLOCK) && (!defined(EDEADLK) || EDEADLOCK != EDEADLK)
    case EDEADLOCK: return 16;
#endif
#ifdef EDESTADDRREQ
    case EDESTADDRREQ: return 17;
#endif
#ifdef EDOM
    case EDOM: return 18;
#endif
#ifdef EDQUOT
    case EDQUOT: return 19;
#endif
#ifdef EEXIST
    case EEXIST: return 20;
#endif
#ifdef EFAULT
    case EFAULT: return 21;
#endif
#ifdef EFBIG
    case EFBIG: return 22;
#endif
#ifdef EILSEQ
    case EILSEQ: return 25;
#endif
#ifdef EINPROGRESS
    case EINPROGRESS: return 26;
#endif
#ifdef EINTR
    case EINTR: return 27;
#endif
#ifdef EINVAL
    case EINVAL: return 28;
#endif
#ifdef EIO
    case EIO: return 29;
#endif
#ifdef EISCONN
    case EISCONN: return 30;
#endif
#ifdef EISDIR
    case EISDIR: return 31;
#endif
#ifdef ELOOP
    case ELOOP: return 32;
#endif
#ifdef EMFILE
    case EMFILE: return 33;
#endif
#ifdef EMLINK
    case EMLINK: return 34;
#endif
#ifdef EMSGSIZE
    case EMSGSIZE: return 35;
#endif
#ifdef ENAMETOOLONG
    case ENAMETOOLONG: return 37;
#endif
#ifdef ENETDOWN
    case ENETDOWN: return 38;
#endif
#ifdef ENETRESET
    case ENETRESET: return 39;
#endif
#ifdef ENETUNREACH
    case ENETUNREACH: return 40;
#endif
#ifdef ENFILE
    case ENFILE: return 41;
#endif
#ifdef ENOBUFS
    case ENOBUFS: return 42;
#endif
#ifdef ENODEV
    case ENODEV: return 43;
#endif
#ifdef ENOENT
    case ENOENT: return 44;
#endif
#ifdef ENOEXEC
    case ENOEXEC: return 45;
#endif
#ifdef ENOLCK
    case ENOLCK: return 46;
#endif
#ifdef ENOMEM
    case ENOMEM: return 48;
#endif
#ifdef ENOMSG
    case ENOMSG: return 49;
#endif
#ifdef ENOPROTOOPT
    case ENOPROTOOPT: return 50;
#endif
#ifdef ENOSPC
    case ENOSPC: return 51;
#endif
#ifdef ENOSYS
    case ENOSYS: return 52;
#endif
#ifdef ENOTCONN
    case ENOTCONN: return 53;
#endif
#ifdef ENOTDIR
    case ENOTDIR: return 54;
#endif
#ifdef ENOTEMPTY
    case ENOTEMPTY: return 55;
#endif
#ifdef ENOTRECOVERABLE
    case ENOTRECOVERABLE: return 56;
#endif
#ifdef ENOTSOCK
    case ENOTSOCK: return 57;
#endif
#ifdef ENOTSUP
    case ENOTSUP: return 58;
#endif
#if defined(EOPNOTSUPP) && (!defined(ENOTSUP) || EOPNOTSUPP != ENOTSUP)
    case EOPNOTSUPP: return 58;
#endif
#ifdef ENOTTY
    case ENOTTY: return 59;
#endif
#ifdef ENXIO
    case ENXIO: return 60;
#endif
#ifdef EOVERFLOW
    case EOVERFLOW: return 61;
#endif
#ifdef EPERM
    case EPERM: return 63;
#endif
#ifdef EPIPE
    case EPIPE: return 64;
#endif
#ifdef EPROTO
    case EPROTO: return 65;
#endif
#ifdef EPROTONOSUPPORT
    case EPROTONOSUPPORT: return 66;
#endif
#ifdef EPROTOTYPE
    case EPROTOTYPE: return 67;
#endif
#ifdef ERANGE
    case ERANGE: return 68;
#endif
#ifdef EROFS
    case EROFS: return 69;
#endif
#ifdef ESPIPE
    case ESPIPE: return 70;
#endif
#ifdef ESRCH
    case ESRCH: return 71;
#endif
#ifdef ETIMEDOUT
    case ETIMEDOUT: return 73;
#endif
#ifdef ETXTBSY
    case ETXTBSY: return 74;
#endif
#ifdef EXDEV
    case EXDEV: return 75;
#endif
    default: return 29;  // EIO fallback
  }
}

// Platform-specific open flags
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_rdonly(void) { return O_RDONLY; }
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_wronly(void) { return O_WRONLY; }
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_rdwr(void) { return O_RDWR; }
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_creat(void) { return O_CREAT; }
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_trunc(void) { return O_TRUNC; }
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_append(void) { return O_APPEND; }
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_excl(void) { return O_EXCL; }
MOONBIT_FFI_EXPORT int wasmoon_wasi_o_nonblock(void) {
#ifdef O_NONBLOCK
  return O_NONBLOCK;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_o_directory(void) {
#ifdef O_DIRECTORY
  return O_DIRECTORY;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_o_nofollow(void) {
#ifdef O_NOFOLLOW
  return O_NOFOLLOW;
#else
  return 0;
#endif
}

// Create a directory
MOONBIT_FFI_EXPORT int wasmoon_wasi_mkdir(moonbit_bytes_t path, int mode) {
#ifdef _WIN32
  (void)mode;  // Windows mkdir doesn't use mode
  return _mkdir((const char *)path);
#else
  return mkdir((const char *)path, mode);
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_mkdirat(
  int dirfd,
  moonbit_bytes_t path,
  int mode
) {
#ifdef _WIN32
  (void)dirfd;
  (void)mode;
  return _mkdir((const char *)path);
#else
  return mkdirat(dirfd, (const char *)path, mode);
#endif
}

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

// Directory entry structure for readdir
// Returns a serialized format: count (4 bytes) + entries
// Each entry: filetype (1 byte) + name_len (4 bytes) + name (variable)
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
    total_size += 1 + 4 + strlen(entry->d_name);  // filetype + name_len + name
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

    result[offset] = wasmoon_wasi_dirent_filetype(dir, entry);
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

MOONBIT_FFI_EXPORT moonbit_bytes_t wasmoon_wasi_readdir_fd(int fd) {
#ifdef _WIN32
  (void)fd;
  moonbit_bytes_t result = moonbit_make_bytes(4, 0);
  memset(result, 0, 4);  // count = 0
  return result;
#else
  int dup_fd = dup(fd);
  if (dup_fd < 0) {
    return NULL;
  }
  DIR *dir = fdopendir(dup_fd);
  if (!dir) {
    close(dup_fd);
    return NULL;
  }

  int count = 0;
  size_t total_size = 4;  // 4 bytes for count
  struct dirent *entry;

  while ((entry = readdir(dir)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    count++;
    total_size += 1 + 4 + strlen(entry->d_name);  // filetype + name_len + name
  }

  moonbit_bytes_t result = moonbit_make_bytes(total_size, 0);
  result[0] = count & 0xFF;
  result[1] = (count >> 8) & 0xFF;
  result[2] = (count >> 16) & 0xFF;
  result[3] = (count >> 24) & 0xFF;

  rewinddir(dir);
  size_t offset = 4;
  while ((entry = readdir(dir)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }

    result[offset] = wasmoon_wasi_dirent_filetype(dir, entry);
    offset++;

    size_t name_len = strlen(entry->d_name);
    result[offset] = name_len & 0xFF;
    result[offset + 1] = (name_len >> 8) & 0xFF;
    result[offset + 2] = (name_len >> 16) & 0xFF;
    result[offset + 3] = (name_len >> 24) & 0xFF;
    offset += 4;

    memcpy(result + offset, entry->d_name, name_len);
    offset += name_len;
  }

  closedir(dir); // closes dup_fd too
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
  // Windows: simple unlink for files, rmdir for directories
  if (flags & WASMOON_AT_REMOVEDIR_TOKEN) {
    return _rmdir((const char *)path);
  } else {
    return _unlink((const char *)path);
  }
#else
  int native_flags = flags;
#ifdef AT_REMOVEDIR
  if (flags & WASMOON_AT_REMOVEDIR_TOKEN) {
    native_flags = (native_flags & ~WASMOON_AT_REMOVEDIR_TOKEN) | AT_REMOVEDIR;
  }
#endif
  return unlinkat(dirfd, (const char *)path, native_flags);
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

  *filetype = wasmoon_wasi_filetype_from_mode(st.st_mode);

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
  int native_flags = flags;
#ifdef AT_SYMLINK_NOFOLLOW
  if (flags & WASMOON_AT_SYMLINK_NOFOLLOW_TOKEN) {
    native_flags =
      (native_flags & ~WASMOON_AT_SYMLINK_NOFOLLOW_TOKEN) | AT_SYMLINK_NOFOLLOW;
  }
#endif
  if (fstatat(dirfd, (const char *)path, &st, native_flags) != 0) {
    return -1;
  }
#endif
  *dev = st.st_dev;
  *ino = st.st_ino;
  *nlink = st.st_nlink;
  *size = st.st_size;

  *filetype = wasmoon_wasi_filetype_from_mode(st.st_mode);

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

  int native_lookup_flags = lookup_flags;
#ifdef AT_SYMLINK_NOFOLLOW
  if (lookup_flags & WASMOON_AT_SYMLINK_NOFOLLOW_TOKEN) {
    native_lookup_flags =
      (native_lookup_flags & ~WASMOON_AT_SYMLINK_NOFOLLOW_TOKEN) | AT_SYMLINK_NOFOLLOW;
  }
#endif
  return utimensat(dirfd, (const char *)path, times, native_lookup_flags);
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
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <signal.h>
#include <time.h>
#endif

static int wasmoon_wasi_socket_family(int family) {
#ifdef _WIN32
  (void)family;
  return -1;
#else
  return family == 4 ? AF_INET : family == 6 ? AF_INET6 : -1;
#endif
}

static int wasmoon_wasi_socket_address(
  int family,
  const uint8_t *address,
  int port,
  int scope_id,
  struct sockaddr_storage *storage,
  socklen_t *length
) {
#ifdef _WIN32
  (void)family;
  (void)address;
  (void)port;
  (void)scope_id;
  (void)storage;
  (void)length;
  errno = ENOTSUP;
  return 0;
#else
  memset(storage, 0, sizeof(*storage));
  if (family == 4) {
    struct sockaddr_in *addr = (struct sockaddr_in *)storage;
    addr->sin_family = AF_INET;
    addr->sin_port = htons((uint16_t)port);
    memcpy(&addr->sin_addr, address, 4);
    *length = sizeof(*addr);
    return 1;
  }
  if (family == 6) {
    struct sockaddr_in6 *addr = (struct sockaddr_in6 *)storage;
    addr->sin6_family = AF_INET6;
    addr->sin6_port = htons((uint16_t)port);
    addr->sin6_scope_id = (uint32_t)scope_id;
    memcpy(&addr->sin6_addr, address, 16);
    *length = sizeof(*addr);
    return 1;
  }
  errno = EAFNOSUPPORT;
  return 0;
#endif
}

#ifndef _WIN32
struct wasmoon_wasi_resolver_address {
  uint8_t family;
  uint8_t address[16];
  uint32_t scope_id;
};

struct wasmoon_wasi_resolver {
  pthread_mutex_t mutex;
  int read_fd;
  int write_fd;
  int completed;
  int dropped;
  int gai_error;
  size_t count;
  size_t index;
  struct wasmoon_wasi_resolver_address *addresses;
  char *name;
};

static void wasmoon_wasi_resolver_free(struct wasmoon_wasi_resolver *resolver) {
  if (resolver->read_fd >= 0) close(resolver->read_fd);
  if (resolver->write_fd >= 0) close(resolver->write_fd);
  free(resolver->addresses);
  free(resolver->name);
  pthread_mutex_destroy(&resolver->mutex);
  free(resolver);
}

static int wasmoon_wasi_is_mapped_ipv4(const struct in6_addr *address) {
  const uint8_t *bytes = (const uint8_t *)address;
  for (int i = 0; i < 10; i++) {
    if (bytes[i] != 0) return 0;
  }
  return bytes[10] == 0xff && bytes[11] == 0xff;
}

static void *wasmoon_wasi_resolver_run(void *argument) {
  struct wasmoon_wasi_resolver *resolver =
    (struct wasmoon_wasi_resolver *)argument;
  struct addrinfo hints;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  struct addrinfo *results = NULL;
  int gai_error = getaddrinfo(resolver->name, NULL, &hints, &results);
  size_t count = 0;
  if (gai_error == 0) {
    for (struct addrinfo *current = results;
         current != NULL;
         current = current->ai_next) {
      if (current->ai_family == AF_INET) {
        count++;
      } else if (current->ai_family == AF_INET6) {
        struct sockaddr_in6 *address =
          (struct sockaddr_in6 *)current->ai_addr;
        if (!wasmoon_wasi_is_mapped_ipv4(&address->sin6_addr)) count++;
      }
    }
  }
  struct wasmoon_wasi_resolver_address *addresses = NULL;
  if (count > 0) {
    addresses = calloc(count, sizeof(*addresses));
    if (addresses == NULL) {
      gai_error = EAI_MEMORY;
      count = 0;
    }
  }
  size_t index = 0;
  if (gai_error == 0) {
    for (struct addrinfo *current = results;
         current != NULL && index < count;
         current = current->ai_next) {
      if (current->ai_family == AF_INET) {
        struct sockaddr_in *address = (struct sockaddr_in *)current->ai_addr;
        addresses[index].family = 4;
        memcpy(addresses[index].address, &address->sin_addr, 4);
        index++;
      } else if (current->ai_family == AF_INET6) {
        struct sockaddr_in6 *address =
          (struct sockaddr_in6 *)current->ai_addr;
        if (wasmoon_wasi_is_mapped_ipv4(&address->sin6_addr)) continue;
        addresses[index].family = 6;
        addresses[index].scope_id = address->sin6_scope_id;
        memcpy(addresses[index].address, &address->sin6_addr, 16);
        index++;
      }
    }
  }
  if (results != NULL) freeaddrinfo(results);

  pthread_mutex_lock(&resolver->mutex);
  resolver->gai_error = gai_error;
  resolver->addresses = addresses;
  resolver->count = index;
  resolver->completed = 1;
  int dropped = resolver->dropped;
  int write_fd = resolver->write_fd;
  resolver->write_fd = -1;
  pthread_mutex_unlock(&resolver->mutex);
  if (write_fd >= 0) {
    uint8_t ready = 1;
    (void)write(write_fd, &ready, sizeof(ready));
    close(write_fd);
  }
  if (dropped) wasmoon_wasi_resolver_free(resolver);
  return NULL;
}
#endif

MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_resolver_start(
  moonbit_bytes_t name,
  int *poll_fd
) {
#ifdef _WIN32
  (void)name;
  (void)poll_fd;
  errno = ENOTSUP;
  return 0;
#else
  int pipe_fds[2];
  if (pipe(pipe_fds) != 0) return 0;
  int flags = fcntl(pipe_fds[0], F_GETFL, 0);
  if (flags < 0 || fcntl(pipe_fds[0], F_SETFL, flags | O_NONBLOCK) != 0) {
    close(pipe_fds[0]);
    close(pipe_fds[1]);
    return 0;
  }
  struct wasmoon_wasi_resolver *resolver = calloc(1, sizeof(*resolver));
  if (resolver == NULL) {
    close(pipe_fds[0]);
    close(pipe_fds[1]);
    return 0;
  }
  resolver->read_fd = pipe_fds[0];
  resolver->write_fd = pipe_fds[1];
  resolver->name = strdup((const char *)name);
  if (resolver->name == NULL || pthread_mutex_init(&resolver->mutex, NULL) != 0) {
    close(pipe_fds[0]);
    close(pipe_fds[1]);
    free(resolver->name);
    free(resolver);
    return 0;
  }
  pthread_t thread;
  if (pthread_create(&thread, NULL, wasmoon_wasi_resolver_run, resolver) != 0) {
    wasmoon_wasi_resolver_free(resolver);
    return 0;
  }
  pthread_detach(thread);
  *poll_fd = resolver->read_fd;
  return (int64_t)(intptr_t)resolver;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_resolver_next(
  int64_t resolver_handle,
  uint8_t *family,
  uint8_t *address,
  uint32_t *scope_id
) {
#ifdef _WIN32
  (void)resolver_handle;
  (void)family;
  (void)address;
  (void)scope_id;
  errno = ENOTSUP;
  return -1;
#else
  struct wasmoon_wasi_resolver *resolver =
    (struct wasmoon_wasi_resolver *)(intptr_t)resolver_handle;
  pthread_mutex_lock(&resolver->mutex);
  if (!resolver->completed) {
    pthread_mutex_unlock(&resolver->mutex);
    return 1;
  }
  if (resolver->gai_error != 0) {
    int error = resolver->gai_error;
    pthread_mutex_unlock(&resolver->mutex);
    if (error == EAI_AGAIN) return 4;
#if defined(EAI_NONAME)
    if (error == EAI_NONAME) return 3;
#endif
#if defined(EAI_NODATA) && EAI_NODATA != EAI_NONAME
    if (error == EAI_NODATA) return 3;
#endif
    return 5;
  }
  if (resolver->index >= resolver->count) {
    pthread_mutex_unlock(&resolver->mutex);
    return 2;
  }
  struct wasmoon_wasi_resolver_address *result =
    &resolver->addresses[resolver->index++];
  *family = result->family;
  memset(address, 0, 16);
  memcpy(address, result->address, result->family == 4 ? 4 : 16);
  *scope_id = result->scope_id;
  pthread_mutex_unlock(&resolver->mutex);
  return 0;
#endif
}

MOONBIT_FFI_EXPORT void wasmoon_wasi_resolver_drop(int64_t resolver_handle) {
#ifndef _WIN32
  struct wasmoon_wasi_resolver *resolver =
    (struct wasmoon_wasi_resolver *)(intptr_t)resolver_handle;
  if (resolver == NULL) return;
  pthread_mutex_lock(&resolver->mutex);
  resolver->dropped = 1;
  int completed = resolver->completed;
  int read_fd = resolver->read_fd;
  resolver->read_fd = -1;
  pthread_mutex_unlock(&resolver->mutex);
  if (read_fd >= 0) close(read_fd);
  if (completed) wasmoon_wasi_resolver_free(resolver);
#else
  (void)resolver_handle;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_create(int family, int kind) {
#ifdef _WIN32
  (void)family;
  (void)kind;
  errno = ENOTSUP;
  return -1;
#else
  int native_family = wasmoon_wasi_socket_family(family);
  if (native_family < 0 || (kind != 1 && kind != 2)) {
    errno = EAFNOSUPPORT;
    return -1;
  }
  int fd = socket(native_family, kind == 1 ? SOCK_STREAM : SOCK_DGRAM, 0);
  if (fd < 0) return -1;
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) {
    close(fd);
    return -1;
  }
  if (native_family == AF_INET6) {
    int enabled = 1;
    if (setsockopt(
      fd,
      IPPROTO_IPV6,
      IPV6_V6ONLY,
      &enabled,
      sizeof(enabled)
    ) != 0) {
      close(fd);
      return -1;
    }
  }
  return fd;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_bind(
  int fd,
  int family,
  moonbit_bytes_t address,
  int port,
  int scope_id
) {
#ifdef _WIN32
  (void)fd;
  (void)family;
  (void)address;
  (void)port;
  (void)scope_id;
  errno = ENOTSUP;
  return -1;
#else
  struct sockaddr_storage storage;
  socklen_t length;
  if (!wasmoon_wasi_socket_address(
    family,
    address,
    port,
    scope_id,
    &storage,
    &length
  )) return -1;
  return bind(fd, (struct sockaddr *)&storage, length);
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_connect(
  int fd,
  int family,
  moonbit_bytes_t address,
  int port,
  int scope_id
) {
#ifdef _WIN32
  (void)fd;
  (void)family;
  (void)address;
  (void)port;
  (void)scope_id;
  errno = ENOTSUP;
  return -1;
#else
  struct sockaddr_storage storage;
  socklen_t length;
  if (!wasmoon_wasi_socket_address(
    family,
    address,
    port,
    scope_id,
    &storage,
    &length
  )) return -1;
  if (connect(fd, (struct sockaddr *)&storage, length) == 0) return 0;
  if (errno == EINPROGRESS || errno == EWOULDBLOCK) return 1;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_disconnect(int fd) {
#ifdef _WIN32
  (void)fd;
  errno = ENOTSUP;
  return -1;
#else
  struct sockaddr_storage storage;
  memset(&storage, 0, sizeof(storage));
  storage.ss_family = AF_UNSPEC;
  return connect(fd, (struct sockaddr *)&storage, sizeof(storage));
#endif
}

MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_socket_recv_from(
  int fd,
  moonbit_bytes_t data,
  int length,
  uint8_t *family,
  uint8_t *address,
  uint16_t *port,
  uint32_t *scope_id
) {
#ifdef _WIN32
  (void)fd;
  (void)data;
  (void)length;
  (void)family;
  (void)address;
  (void)port;
  (void)scope_id;
  errno = ENOTSUP;
  return -1;
#else
  struct sockaddr_storage storage;
  socklen_t storage_length = sizeof(storage);
  ssize_t received = recvfrom(
    fd,
    data,
    (size_t)length,
    0,
    (struct sockaddr *)&storage,
    &storage_length
  );
  if (received < 0) return -1;
  memset(address, 0, 16);
  if (storage.ss_family == AF_INET) {
    struct sockaddr_in *addr = (struct sockaddr_in *)&storage;
    *family = 4;
    *port = ntohs(addr->sin_port);
    *scope_id = 0;
    memcpy(address, &addr->sin_addr, 4);
  } else if (storage.ss_family == AF_INET6) {
    struct sockaddr_in6 *addr = (struct sockaddr_in6 *)&storage;
    *family = 6;
    *port = ntohs(addr->sin6_port);
    *scope_id = addr->sin6_scope_id;
    memcpy(address, &addr->sin6_addr, 16);
  } else {
    errno = EAFNOSUPPORT;
    return -1;
  }
  return (int64_t)received;
#endif
}

MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_socket_send_to(
  int fd,
  moonbit_bytes_t data,
  int length,
  int has_address,
  int family,
  moonbit_bytes_t address,
  int port,
  int scope_id
) {
#ifdef _WIN32
  (void)fd;
  (void)data;
  (void)length;
  (void)has_address;
  (void)family;
  (void)address;
  (void)port;
  (void)scope_id;
  errno = ENOTSUP;
  return -1;
#else
  if (!has_address) {
    return (int64_t)send(fd, data, (size_t)length, 0);
  }
  struct sockaddr_storage storage;
  socklen_t storage_length;
  if (!wasmoon_wasi_socket_address(
    family,
    address,
    port,
    scope_id,
    &storage,
    &storage_length
  )) return -1;
  return (int64_t)sendto(
    fd,
    data,
    (size_t)length,
    0,
    (struct sockaddr *)&storage,
    storage_length
  );
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_listen(int fd, int backlog) {
#ifdef _WIN32
  (void)fd;
  (void)backlog;
  errno = ENOTSUP;
  return -1;
#else
  return listen(fd, backlog);
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_error(int fd) {
#ifdef _WIN32
  (void)fd;
  errno = ENOTSUP;
  return -1;
#else
  int error = 0;
  socklen_t length = sizeof(error);
  if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) != 0) return -1;
  return error;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_address_get(
  int fd,
  int peer,
  uint8_t *family,
  uint8_t *address,
  uint16_t *port,
  uint32_t *scope_id
) {
#ifdef _WIN32
  (void)fd;
  (void)peer;
  (void)family;
  (void)address;
  (void)port;
  (void)scope_id;
  errno = ENOTSUP;
  return -1;
#else
  struct sockaddr_storage storage;
  socklen_t length = sizeof(storage);
  int result = peer
    ? getpeername(fd, (struct sockaddr *)&storage, &length)
    : getsockname(fd, (struct sockaddr *)&storage, &length);
  if (result != 0) return -1;
  memset(address, 0, 16);
  if (storage.ss_family == AF_INET) {
    struct sockaddr_in *addr = (struct sockaddr_in *)&storage;
    *family = 4;
    *port = ntohs(addr->sin_port);
    *scope_id = 0;
    memcpy(address, &addr->sin_addr, 4);
    return 0;
  }
  if (storage.ss_family == AF_INET6) {
    struct sockaddr_in6 *addr = (struct sockaddr_in6 *)&storage;
    *family = 6;
    *port = ntohs(addr->sin6_port);
    *scope_id = addr->sin6_scope_id;
    memcpy(address, &addr->sin6_addr, 16);
    return 0;
  }
  errno = EAFNOSUPPORT;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_option_get(
  int fd,
  int family,
  int option
) {
#ifdef _WIN32
  (void)fd;
  (void)family;
  (void)option;
  errno = ENOTSUP;
  return -1;
#else
  int level = SOL_SOCKET;
  int native_option = 0;
  switch (option) {
    case 0: native_option = SO_KEEPALIVE; break;
    case 1:
      level = IPPROTO_TCP;
#if defined(__APPLE__)
      native_option = TCP_KEEPALIVE;
#else
      native_option = TCP_KEEPIDLE;
#endif
      break;
    case 2: level = IPPROTO_TCP; native_option = TCP_KEEPINTVL; break;
    case 3: level = IPPROTO_TCP; native_option = TCP_KEEPCNT; break;
    case 4:
      level = family == 6 ? IPPROTO_IPV6 : IPPROTO_IP;
      native_option = family == 6 ? IPV6_UNICAST_HOPS : IP_TTL;
      break;
    case 5: native_option = SO_RCVBUF; break;
    case 6: native_option = SO_SNDBUF; break;
    case 7: native_option = SO_REUSEADDR; break;
    default: errno = EINVAL; return -1;
  }
  int value = 0;
  socklen_t length = sizeof(value);
  if (getsockopt(fd, level, native_option, &value, &length) != 0) return -1;
  return value;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_option_set(
  int fd,
  int family,
  int option,
  int value
) {
#ifdef _WIN32
  (void)fd;
  (void)family;
  (void)option;
  (void)value;
  errno = ENOTSUP;
  return -1;
#else
  int level = SOL_SOCKET;
  int native_option = 0;
  switch (option) {
    case 0: native_option = SO_KEEPALIVE; break;
    case 1:
      level = IPPROTO_TCP;
#if defined(__APPLE__)
      native_option = TCP_KEEPALIVE;
#else
      native_option = TCP_KEEPIDLE;
#endif
      break;
    case 2: level = IPPROTO_TCP; native_option = TCP_KEEPINTVL; break;
    case 3: level = IPPROTO_TCP; native_option = TCP_KEEPCNT; break;
    case 4:
      level = family == 6 ? IPPROTO_IPV6 : IPPROTO_IP;
      native_option = family == 6 ? IPV6_UNICAST_HOPS : IP_TTL;
      break;
    case 5: native_option = SO_RCVBUF; break;
    case 6: native_option = SO_SNDBUF; break;
    case 7: native_option = SO_REUSEADDR; break;
    default: errno = EINVAL; return -1;
  }
  return setsockopt(fd, level, native_option, &value, sizeof(value));
#endif
}

// Nanosleep - sleep for specified nanoseconds
// Returns 0 on success, -1 on error
MOONBIT_FFI_EXPORT int wasmoon_wasi_nanosleep(int64_t ns) {
#ifdef _WIN32
  // Windows: use Sleep (milliseconds)
  DWORD millis = ns <= 0 ? 0 : (DWORD)(ns / 1000000 + (ns % 1000000 != 0));
  Sleep(millis);
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

MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_clock_getres_monotonic(void) {
#ifdef _WIN32
  LARGE_INTEGER freq;
  if (!QueryPerformanceFrequency(&freq) || freq.QuadPart <= 0) {
    return -1;
  }
  return (int64_t)(1000000000LL / freq.QuadPart);
#else
  struct timespec ts;
  if (clock_getres(CLOCK_MONOTONIC, &ts) != 0) {
    return -1;
  }
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
}

MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_clock_getres_realtime(void) {
#ifdef _WIN32
  // Windows wall clock resolution is not exposed directly. Use 1ms as fallback.
  return 1000000;
#else
  struct timespec ts;
  if (clock_getres(CLOCK_REALTIME, &ts) != 0) {
    return -1;
  }
  return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
}

// Poll on file descriptors
// fds_ptr: array of (fd, events) pairs
// nfds: number of fds
// timeout_ms: timeout in milliseconds (-1 for infinite)
// Returns number of ready fds, or -1 on error
MOONBIT_FFI_EXPORT int wasmoon_wasi_poll(int* fds_ptr, int* events_ptr,
    int* revents_ptr, int nfds, int timeout_ms) {
#ifdef _WIN32
  (void)fds_ptr;
  (void)events_ptr;
  (void)revents_ptr;
  (void)nfds;
  (void)timeout_ms;
  errno = ENOSYS;
  return -1;
#else
  if (nfds <= 0) {
    errno = EINVAL;
    return -1;
  }

  struct pollfd *pfds = calloc((size_t)nfds, sizeof(struct pollfd));
  if (!pfds) return -1;
  for (int i = 0; i < nfds; i++) {
    pfds[i].fd = fds_ptr[i];
    pfds[i].events = (short)events_ptr[i];
    pfds[i].revents = 0;
  }

  int result = poll(pfds, nfds, timeout_ms);

  for (int i = 0; i < nfds; i++) {
    revents_ptr[i] = (int)pfds[i].revents;
  }

  free(pfds);
  return result;
#endif
}

// Number of bytes currently readable from a socket, or -1 on error.
MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_socket_bytes_available(int fd) {
#ifdef _WIN32
  (void)fd;
  errno = ENOSYS;
  return -1;
#else
  int available = 0;
  if (ioctl(fd, FIONREAD, &available) != 0) return -1;
  return (int64_t)available;
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
  int fd = accept(sockfd, NULL, NULL);
  if (fd < 0) return -1;
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) {
    close(fd);
    return -1;
  }
  return fd;
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
