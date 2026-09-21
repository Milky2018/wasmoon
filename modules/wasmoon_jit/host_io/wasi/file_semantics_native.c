#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <errno.h>
#include <stdint.h>
#include <fcntl.h>
#include <sys/stat.h>
#include "moonbit.h"
#ifdef _WIN32
#include "../windows_io.h"
#include "../windows_fs.h"
#else
#include <unistd.h>
#endif

// Return errno directly so cleanup cannot replace the operation's error.
MOONBIT_FFI_EXPORT int wasmoon_wasi_allocate(int fd, int64_t offset, int64_t length) {
  if (offset < 0 || length < 0 || offset > INT64_MAX - length) return EOVERFLOW;
  if (length == 0) return EINVAL;
  int64_t end = offset + length;
#ifdef _WIN32
  int flags = wasmoon_windows_getfl(fd);
  if (flags < 0) return errno;
  if (!(flags & (_O_WRONLY | _O_RDWR))) return EBADF;
  HANDLE handle = wasmoon_windows_fd_handle(fd);
  if (handle == INVALID_HANDLE_VALUE) return errno;
  FILE_BASIC_INFO attributes;
  if (!GetFileInformationByHandleEx(handle, FileBasicInfo, &attributes, sizeof(attributes))) {
    wasmoon_windows_error(GetLastError()); return errno;
  }
  // AllocationSize does not reserve individual ranges in sparse/compressed files.
  if (attributes.FileAttributes & (FILE_ATTRIBUTE_SPARSE_FILE | FILE_ATTRIBUTE_COMPRESSED)) return ENOTSUP;
  FILE_STANDARD_INFO before;
  if (!GetFileInformationByHandleEx(handle, FileStandardInfo, &before, sizeof(before))) {
    wasmoon_windows_error(GetLastError()); return errno;
  }
  FILE_ALLOCATION_INFO allocation;
  allocation.AllocationSize.QuadPart = end > before.AllocationSize.QuadPart
    ? end : before.AllocationSize.QuadPart;
  if (!SetFileInformationByHandle(handle, FileAllocationInfo, &allocation, sizeof(allocation))) {
    wasmoon_windows_error(GetLastError()); return errno;
  }
  if (end > before.EndOfFile.QuadPart && wasmoon_windows_ftruncate(fd, end) != 0) return errno;
  return 0;
#elif defined(__APPLE__)
  int flags = fcntl(fd, F_GETFL);
  if (flags < 0) return errno;
  if ((flags & O_ACCMODE) == O_RDONLY) return EBADF;
  struct stat before;
  if (fstat(fd, &before) != 0) return errno;
  // F_PREALLOCATE grows from physical EOF, not an arbitrary logical hole.
  // Reject sparse files before any allocation or extension. Total st_blocks
  // alone cannot establish that the requested logical range is backed.
  if (before.st_size > 0) {
    off_t saved = lseek(fd, 0, SEEK_CUR);
    if (saved < 0) return errno;
    off_t hole = lseek(fd, 0, SEEK_HOLE);
    int query_error = hole < 0 ? errno : 0;
    if (lseek(fd, saved, SEEK_SET) < 0) return errno;
    if (query_error) return query_error;
    if (hole < before.st_size) return ENOTSUP;
  }
  int64_t allocated = before.st_blocks > INT64_MAX / 512
    ? INT64_MAX : (int64_t)before.st_blocks * 512;
  fstore_t allocation = {0};
  allocation.fst_flags = F_ALLOCATEALL;
#ifdef F_ALLOCATEPERSIST
  allocation.fst_flags |= F_ALLOCATEPERSIST;
#endif
  allocation.fst_posmode = F_PEOFPOSMODE;
  allocation.fst_offset = 0;
  allocation.fst_length = end > allocated ? end - allocated : 0;
  if (allocation.fst_length && fcntl(fd, F_PREALLOCATE, &allocation) != 0) return errno;
  if (end > before.st_size && ftruncate(fd, end) != 0) return errno;
  return 0;
#elif defined(__linux__)
  return fallocate(fd, 0, (off_t)offset, (off_t)length) == 0 ? 0 : errno;
#else
  return posix_fallocate(fd, (off_t)offset, (off_t)length);
#endif
}
