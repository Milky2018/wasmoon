#ifdef _WIN32
#include "windows_fs.h"
#include <winternl.h>
#include <winioctl.h>
#include <errno.h>
#include <io.h>
#include <stdlib.h>
#include <string.h>

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
  else if (flags & _O_TRUNC) {
    int error = _chsize_s(fd, 0);
    if (error) { _close(fd); errno = error; return -1; }
  }
  return fd;
}
int wasmoon_windows_open(const char *path, int flags, int mode) {
  (void)mode;
  wchar_t *name = wasmoon_windows_utf16(path);
  if (!name) return -1;
  // Truncate only after verifying no-follow and directory constraints.
  DWORD disposition = flags & _O_CREAT ? (flags & _O_EXCL ? CREATE_NEW : OPEN_ALWAYS) : OPEN_EXISTING;
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
  ULONG disposition = flags & _O_CREAT ? (flags & _O_EXCL ? 2 : 3) : 1;
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

static wchar_t *canonical_existing_path(const wchar_t *path) {
  HANDLE handle = CreateFileW(path, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
  if (handle == INVALID_HANDLE_VALUE) return NULL;
  DWORD length = GetFinalPathNameByHandleW(handle, NULL, 0, FILE_NAME_NORMALIZED);
  wchar_t *result = length ? malloc(((size_t)length + 1) * sizeof(*result)) : NULL;
  if (!result || !GetFinalPathNameByHandleW(handle, result, length + 1, FILE_NAME_NORMALIZED)) {
    free(result); result = NULL;
  }
  DWORD error = GetLastError();
  CloseHandle(handle); SetLastError(error);
  return result;
}
int wasmoon_windows_path_within_base(const char *base, const char *target) {
  wchar_t *base_wide = wasmoon_windows_utf16(base);
  wchar_t *target_wide = wasmoon_windows_utf16(target);
  if (!base_wide || !target_wide) { free(base_wide); free(target_wide); return 0; }
  wchar_t *base_final = canonical_existing_path(base_wide);
  free(base_wide);
  if (!base_final) { free(target_wide); return 0; }
  wchar_t *absolute = _wfullpath(NULL, target_wide, 0);
  free(target_wide);
  if (!absolute) { free(base_final); return 0; }
  wchar_t *target_final = NULL;
  for (;;) {
    target_final = canonical_existing_path(absolute);
    if (target_final) break;
    DWORD error = GetLastError();
    if (error != ERROR_FILE_NOT_FOUND && error != ERROR_PATH_NOT_FOUND) break;
    wchar_t *last = wcsrchr(absolute, L'\\');
    if (!last || last <= absolute + 2) break;
    *last = L'\0';
  }
  free(absolute);
  size_t length = wcslen(base_final);
  while (length && base_final[length - 1] == L'\\') length--;
  int within = target_final && wcslen(target_final) >= length &&
      CompareStringOrdinal(base_final, (int)length, target_final, (int)length, TRUE) == CSTR_EQUAL &&
      (target_final[length] == 0 || target_final[length] == L'\\');
  free(base_final); free(target_final);
  return within;
}
unsigned char *wasmoon_windows_directory_entries(int fd, int *length) {
  HANDLE handle = open_relative(fd, ".", FILE_LIST_DIRECTORY | FILE_READ_ATTRIBUTES, 1, 1);
  if (handle == INVALID_HANDLE_VALUE) return NULL;
  union { uint64_t align; unsigned char bytes[65536]; } entries;
  size_t capacity = 256, used = 4;
  uint32_t count = 0;
  unsigned char *result = malloc(capacity);
  if (!result) { CloseHandle(handle); errno = ENOMEM; return NULL; }
  FILE_INFO_BY_HANDLE_CLASS query = FileIdBothDirectoryRestartInfo;
  for (;;) {
    if (!GetFileInformationByHandleEx(handle, query, entries.bytes, sizeof(entries.bytes))) {
      DWORD error = GetLastError();
      if (error == ERROR_NO_MORE_FILES) break;
      wasmoon_windows_error(error); goto fail;
    }
    query = FileIdBothDirectoryInfo;
    size_t offset = 0;
    for (;;) {
      FILE_ID_BOTH_DIR_INFO *entry = (FILE_ID_BOTH_DIR_INFO *)(entries.bytes + offset);
      size_t header = offsetof(FILE_ID_BOTH_DIR_INFO, FileName);
      if (offset > sizeof(entries.bytes) - header || entry->FileNameLength & 1 ||
          entry->FileNameLength > sizeof(entries.bytes) - offset - header) { errno = EIO; goto fail; }
      int characters = (int)(entry->FileNameLength / sizeof(wchar_t));
      if (!((characters == 1 && entry->FileName[0] == L'.') ||
            (characters == 2 && entry->FileName[0] == L'.' && entry->FileName[1] == L'.'))) {
        int bytes = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, entry->FileName, characters,
                                       NULL, 0, NULL, NULL);
        if (!bytes) { errno = EILSEQ; goto fail; }
        size_t required = used + 5 + (size_t)bytes;
        if (required > INT32_MAX) { errno = EOVERFLOW; goto fail; }
        if (required > capacity) {
          size_t next = capacity * 2;
          if (next < required) next = required;
          unsigned char *grown = realloc(result, next);
          if (!grown) { errno = ENOMEM; goto fail; }
          result = grown; capacity = next;
        }
        result[used++] = entry->FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT ? 7 :
                        entry->FileAttributes & FILE_ATTRIBUTE_DIRECTORY ? 3 : 4;
        for (int i = 0; i < 4; i++) result[used++] = (bytes >> (8 * i)) & 0xff;
        if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, entry->FileName, characters,
                                (char *)result + used, bytes, NULL, NULL)) { errno = EILSEQ; goto fail; }
        used += bytes; count++;
      }
      if (!entry->NextEntryOffset) break;
      if (entry->NextEntryOffset < header || entry->NextEntryOffset > sizeof(entries.bytes) - offset - header) {
        errno = EIO; goto fail;
      }
      offset += entry->NextEntryOffset;
    }
  }
  CloseHandle(handle);
  for (int i = 0; i < 4; i++) result[i] = (count >> (8 * i)) & 0xff;
  *length = (int)used;
  return result;
fail: {
  int error = errno;
  CloseHandle(handle); free(result); errno = error;
  return NULL;
}
}
#endif
