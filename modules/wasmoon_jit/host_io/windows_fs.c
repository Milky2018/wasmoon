#ifdef _WIN32
#include "windows_fs.h"
#include <winternl.h>
#include <winioctl.h>
#include <errno.h>
#include <io.h>
#include <stdlib.h>
#include <string.h>

int wasmoon_windows_error(DWORD error) {
  switch (error) {
    case ERROR_FILE_NOT_FOUND: case ERROR_PATH_NOT_FOUND: errno = ENOENT; break;
    case ERROR_ACCESS_DENIED: case ERROR_SHARING_VIOLATION: errno = EACCES; break;
    case ERROR_INVALID_HANDLE: errno = EBADF; break;
    case ERROR_ALREADY_EXISTS: case ERROR_FILE_EXISTS: errno = EEXIST; break;
    case ERROR_DIRECTORY: errno = ENOTDIR; break;
    case ERROR_DIR_NOT_EMPTY: errno = ENOTEMPTY; break;
    case ERROR_DISK_FULL: case ERROR_HANDLE_DISK_FULL: errno = ENOSPC; break;
    case ERROR_NOT_ENOUGH_MEMORY: case ERROR_OUTOFMEMORY: errno = ENOMEM; break;
    case ERROR_FILENAME_EXCED_RANGE: errno = ENAMETOOLONG; break;
    case ERROR_INVALID_NAME: case ERROR_INVALID_PARAMETER: errno = EINVAL; break;
    case ERROR_NOT_SAME_DEVICE: errno = EXDEV; break;
    case ERROR_TOO_MANY_OPEN_FILES: errno = EMFILE; break;
    case ERROR_NOT_SUPPORTED: case ERROR_INVALID_FUNCTION: errno = ENOTSUP; break;
    case ERROR_CANT_RESOLVE_FILENAME: case ERROR_STOPPED_ON_SYMLINK: errno = ELOOP; break;
    case ERROR_BROKEN_PIPE: case ERROR_NO_DATA: errno = EPIPE; break;
    case ERROR_OPERATION_ABORTED: errno = EINTR; break;
    default: errno = EIO; break;
  }
  return -1;
}
wchar_t *wasmoon_windows_utf16(const char *text) {
  int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
  if (!length) { errno = EILSEQ; return NULL; }
  wchar_t *result = malloc((size_t)length * sizeof(*result));
  if (!result) { errno = ENOMEM; return NULL; }
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, result, length)) {
    free(result); errno = EILSEQ; return NULL;
  }
  return result;
}
static DWORD open_access(int flags) {
  if (flags & _O_RDWR) return GENERIC_READ | GENERIC_WRITE;
  if (flags & _O_WRONLY) return GENERIC_WRITE;
  return GENERIC_READ;
}
static int adopt_file(HANDLE handle, int flags) {
  if (handle == INVALID_HANDLE_VALUE) return wasmoon_windows_error(GetLastError());
  FILE_ATTRIBUTE_TAG_INFO attributes;
  if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfo, &attributes, sizeof(attributes))) {
    // Pipes and console handles have no file attributes.
    if (GetFileType(handle) == FILE_TYPE_DISK) {
      DWORD error = GetLastError(); CloseHandle(handle); return wasmoon_windows_error(error);
    }
    attributes.FileAttributes = 0;
  }
  if ((flags & WASMOON_O_NOFOLLOW) && (attributes.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
    CloseHandle(handle); errno = ELOOP; return -1;
  }
  if ((flags & WASMOON_O_DIRECTORY) && !(attributes.FileAttributes & FILE_ATTRIBUTE_DIRECTORY)) {
    CloseHandle(handle); errno = ENOTDIR; return -1;
  }
  int fd = _open_osfhandle((intptr_t)handle,
      (flags & (_O_RDONLY | _O_WRONLY | _O_RDWR | _O_APPEND)) | _O_BINARY | _O_NOINHERIT);
  if (fd < 0) CloseHandle(handle);
  return fd;
}
int wasmoon_windows_open(const char *path, int flags, int mode) {
  (void)mode;
  wchar_t *name = wasmoon_windows_utf16(path);
  if (!name) return -1;
  DWORD disposition = flags & _O_CREAT ? (flags & _O_EXCL ? CREATE_NEW :
      flags & _O_TRUNC ? CREATE_ALWAYS : OPEN_ALWAYS) : flags & _O_TRUNC ? TRUNCATE_EXISTING : OPEN_EXISTING;
  DWORD attributes = FILE_FLAG_BACKUP_SEMANTICS;
  if (flags & WASMOON_O_NOFOLLOW) attributes |= FILE_FLAG_OPEN_REPARSE_POINT;
  HANDLE handle = CreateFileW(name, open_access(flags), FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              NULL, disposition, attributes, NULL);
  DWORD error = GetLastError();
  free(name);
  if (handle == INVALID_HANDLE_VALUE) return wasmoon_windows_error(error);
  return adopt_file(handle, flags);
}

typedef NTSTATUS (NTAPI *create_file_fn)(PHANDLE, ACCESS_MASK, POBJECT_ATTRIBUTES,
    PIO_STATUS_BLOCK, PLARGE_INTEGER, ULONG, ULONG, ULONG, ULONG, PVOID, ULONG);
typedef ULONG (WINAPI *status_error_fn)(NTSTATUS);
static create_file_fn create_file;
static status_error_fn status_error;
static INIT_ONCE file_once = INIT_ONCE_STATIC_INIT;
static BOOL CALLBACK initialize_file_api(PINIT_ONCE once, PVOID parameter, PVOID *context) {
  (void)once; (void)parameter; (void)context;
  HMODULE module = GetModuleHandleW(L"ntdll.dll");
  create_file = (create_file_fn)GetProcAddress(module, "NtCreateFile");
  status_error = (status_error_fn)GetProcAddress(module, "RtlNtStatusToDosError");
  return TRUE;
}
// Only one guest component may reach this primitive. Directory traversal and
// symlink expansion are performed by the shared capability walker above it.
static HANDLE open_relative(int fd, const char *name, ACCESS_MASK access,
                             ULONG disposition, ULONG options) {
  if (!name || !*name || strchr(name, '/') || strchr(name, '\\') || strchr(name, ':') ||
      !strcmp(name, "..")) { errno = EPERM; return INVALID_HANDLE_VALUE; }
  HANDLE root = wasmoon_windows_fd_handle(fd);
  if (root == INVALID_HANDLE_VALUE) return root;
  wchar_t *wide = wasmoon_windows_utf16(!strcmp(name, ".") ? "" : name);
  if (!wide) return INVALID_HANDLE_VALUE;
  size_t bytes = wcslen(wide) * sizeof(*wide);
  if (bytes > UINT16_MAX - sizeof(wchar_t)) {
    free(wide); errno = ENAMETOOLONG; return INVALID_HANDLE_VALUE;
  }
  InitOnceExecuteOnce(&file_once, initialize_file_api, NULL, NULL);
  if (!create_file || !status_error) { free(wide); errno = ENOTSUP; return INVALID_HANDLE_VALUE; }
  UNICODE_STRING unicode = {(USHORT)bytes, (USHORT)(bytes + sizeof(wchar_t)), wide};
  OBJECT_ATTRIBUTES object = {sizeof(object), root, &unicode, 0x40, NULL, NULL};
  IO_STATUS_BLOCK io;
  HANDLE handle;
  NTSTATUS result = create_file(&handle, access | SYNCHRONIZE, &object, &io, NULL,
      FILE_ATTRIBUTE_NORMAL, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      disposition, options | 0x20 /* FILE_SYNCHRONOUS_IO_NONALERT */, NULL, 0);
  free(wide);
  if (result < 0) { wasmoon_windows_error(status_error(result)); return INVALID_HANDLE_VALUE; }
  return handle;
}
int wasmoon_windows_openat(int fd, const char *name, int flags, int mode) {
  (void)mode;
  ULONG disposition = flags & _O_CREAT ? (flags & _O_EXCL ? 2 : flags & _O_TRUNC ? 5 : 3)
                                       : flags & _O_TRUNC ? 4 : 1;
  ULONG options = (flags & WASMOON_O_NOFOLLOW) ? 0x00200000 : 0;
  // Open reparse points themselves before checking directory-ness: otherwise
  // a directory symlink can be mistaken for an ordinary non-directory error.
  HANDLE handle = open_relative(fd, name, open_access(flags), disposition, options);
  if (handle == INVALID_HANDLE_VALUE) return -1;
  return adopt_file(handle, flags);
}
int wasmoon_windows_is_symlink_at(int fd, const char *name) {
  HANDLE handle = open_relative(fd, name, FILE_READ_ATTRIBUTES, 1, 0x00200000);
  if (handle == INVALID_HANDLE_VALUE) return 0;
  FILE_ATTRIBUTE_TAG_INFO attributes;
  int result = GetFileInformationByHandleEx(handle, FileAttributeTagInfo, &attributes, sizeof(attributes)) &&
               (attributes.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT);
  CloseHandle(handle);
  return result;
}
int64_t wasmoon_windows_readlinkat(int fd, const char *name, char *buffer, size_t capacity) {
  HANDLE handle = open_relative(fd, name, FILE_READ_ATTRIBUTES, 1, 0x00200000);
  if (handle == INVALID_HANDLE_VALUE) return -1;
  union { uint64_t align; unsigned char bytes[MAXIMUM_REPARSE_DATA_BUFFER_SIZE]; } data;
  DWORD length;
  BOOL ok = DeviceIoControl(handle, FSCTL_GET_REPARSE_POINT, NULL, 0, data.bytes,
                            sizeof(data.bytes), &length, NULL);
  DWORD error = GetLastError();
  CloseHandle(handle);
  if (!ok) return wasmoon_windows_error(error);
  // REPARSE_DATA_BUFFER's symbolic-link layout: tag/header, four UTF-16
  // offset/length words, flags, and the shared path buffer.
  if (length < 20) { errno = EIO; return -1; }
  DWORD tag; memcpy(&tag, data.bytes, 4);
  if (tag != IO_REPARSE_TAG_SYMLINK) { errno = ELOOP; return -1; }
  USHORT offset, bytes; DWORD flags;
  memcpy(&offset, data.bytes + 8, 2); memcpy(&bytes, data.bytes + 10, 2);
  memcpy(&flags, data.bytes + 16, 4);
  if (!(flags & 1)) { errno = EPERM; return -1; }
  if ((offset | bytes) & 1 || (size_t)offset + bytes > length - 20) { errno = EIO; return -1; }
  wchar_t *target = (wchar_t *)(data.bytes + 20 + offset);
  int required = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, target, bytes / 2,
                                    NULL, 0, NULL, NULL);
  if (!required) { errno = EILSEQ; return -1; }
  char *utf8 = malloc((size_t)required);
  if (!utf8) { errno = ENOMEM; return -1; }
  if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, target, bytes / 2, utf8, required, NULL, NULL)) {
    free(utf8); errno = EILSEQ; return -1;
  }
  // NT separators are guest path separators, never an ambient Windows path.
  for (int i = 0; i < required; i++) if (utf8[i] == '\\') utf8[i] = '/';
  size_t copied = (size_t)required < capacity ? (size_t)required : capacity;
  memcpy(buffer, utf8, copied); free(utf8);
  return (int64_t)copied;
}
#endif
