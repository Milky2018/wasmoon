#ifdef _WIN32
#include "windows_fs.h"
#include <winternl.h>
#include <winioctl.h>
#include <errno.h>
#include <io.h>
#include <stdlib.h>
#include <string.h>
#pragma comment(lib, "advapi32.lib")

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
  if ((attributes.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) && (flags & (_O_WRONLY | _O_RDWR))) {
    CloseHandle(handle); errno = EISDIR; return -1;
  }
  int fd = _open_osfhandle((intptr_t)handle,
      (flags & (_O_RDONLY | _O_WRONLY | _O_RDWR | _O_APPEND)) | _O_BINARY | _O_NOINHERIT);
  if (fd < 0) CloseHandle(handle);
  else if (flags & _O_TRUNC) {
    if (wasmoon_windows_ftruncate(fd, 0) < 0) {
      int error = errno; _close(fd); errno = error; return -1;
    }
  }
  if (fd >= 0 && wasmoon_windows_track_file(fd, flags) < 0) {
    _close(fd); errno = ENOMEM; return -1;
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
typedef NTSTATUS (NTAPI *set_information_fn)(HANDLE, PIO_STATUS_BLOCK, PVOID, ULONG, FILE_INFORMATION_CLASS);
static create_file_fn create_file;
static status_error_fn status_error;
static set_information_fn set_information;
static INIT_ONCE file_once = INIT_ONCE_STATIC_INIT;
static BOOL CALLBACK initialize_file_api(PINIT_ONCE once, PVOID parameter, PVOID *context) {
  (void)once; (void)parameter; (void)context;
  HMODULE module = GetModuleHandleW(L"ntdll.dll");
  create_file = (create_file_fn)GetProcAddress(module, "NtCreateFile");
  status_error = (status_error_fn)GetProcAddress(module, "RtlNtStatusToDosError");
  set_information = (set_information_fn)GetProcAddress(module, "NtSetInformationFile");
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
static int absolute_path(const char *path) {
  return path[0] == '/' || path[0] == '\\' || (path[0] && path[1] == ':');
}
static wchar_t *nt_absolute_name(const wchar_t *path) {
  wchar_t *full = _wfullpath(NULL, path, 0);
  if (!full) return NULL;
  int unc = full[0] == L'\\' && full[1] == L'\\';
  const wchar_t *suffix = unc ? full + 2 : full;
  const wchar_t *prefix = unc ? L"\\??\\UNC\\" : L"\\??\\";
  size_t length = wcslen(prefix) + wcslen(suffix) + 1;
  wchar_t *name = malloc(length * sizeof(*name));
  if (name) { wcscpy(name, prefix); wcscat(name, suffix); }
  else errno = ENOMEM;
  free(full);
  return name;
}
// Win32 reports PATH_NOT_FOUND for both a missing parent and a file used as
// a directory. Preserve the latter distinction at the portable WASI boundary.
static void path_open_error(const wchar_t *path, DWORD error) {
  if (error == ERROR_PATH_NOT_FOUND) {
    wchar_t *parent = _wfullpath(NULL, path, 0);
    if (parent) {
      for (;;) {
        wchar_t *last = wcsrchr(parent, L'\\');
        if (!last || last <= parent + 2) break;
        *last = 0;
        DWORD attributes = GetFileAttributesW(parent);
        if (attributes != INVALID_FILE_ATTRIBUTES) {
          if (!(attributes & FILE_ATTRIBUTE_DIRECTORY)) {
            free(parent); errno = ENOTDIR; return;
          }
          break;
        }
        DWORD parent_error = GetLastError();
        if (parent_error != ERROR_FILE_NOT_FOUND && parent_error != ERROR_PATH_NOT_FOUND) break;
      }
      free(parent);
    }
  }
  wasmoon_windows_error(error);
}
static HANDLE open_path_or_relative(int fd, const char *path, ACCESS_MASK access,
                                    ULONG disposition, ULONG options) {
  if (!absolute_path(path)) return open_relative(fd, path, access, disposition, options);
  wchar_t *wide = wasmoon_windows_utf16(path);
  if (!wide) return INVALID_HANDLE_VALUE;
  HANDLE handle = CreateFileW(wide, access, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      NULL, disposition == 2 ? CREATE_NEW : OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS | ((options & 0x00200000) ? FILE_FLAG_OPEN_REPARSE_POINT : 0), NULL);
  DWORD error = GetLastError();
  if (handle == INVALID_HANDLE_VALUE) path_open_error(wide, error);
  free(wide);
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
  HANDLE handle = open_path_or_relative(fd, name, FILE_READ_ATTRIBUTES, 1, 0x00200000);
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
  if (!(flags & 1)) {
    // Preserve the caller-visible spelling of absolute links. The capability
    // walker rejects absolute targets; readlink itself must still return them.
    USHORT print_offset, print_bytes;
    memcpy(&print_offset, data.bytes + 12, 2); memcpy(&print_bytes, data.bytes + 14, 2);
    if (print_bytes) { offset = print_offset; bytes = print_bytes; }
  }
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

static BOOL set_symlink_reparse(HANDLE file, void *data, DWORD size) {
  DWORD returned;
  if (DeviceIoControl(file, FSCTL_SET_REPARSE_POINT, data, size, NULL, 0, &returned, NULL)) return TRUE;
  if (GetLastError() != ERROR_PRIVILEGE_NOT_HELD) return FALSE;
  // Enable an already-granted privilege only on a private impersonation token.
  // Other host threads and the caller's token retain their original privileges.
  HANDLE previous = NULL, source = NULL, token = NULL;
  BOOL had_thread_token = OpenThreadToken(GetCurrentThread(),
      TOKEN_QUERY | TOKEN_DUPLICATE | TOKEN_IMPERSONATE, TRUE, &previous);
  if (had_thread_token) source = previous;
  else if (GetLastError() != ERROR_NO_TOKEN ||
           !OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY | TOKEN_DUPLICATE, &source)) return FALSE;
  BOOL ok = DuplicateTokenEx(source, TOKEN_QUERY | TOKEN_ADJUST_PRIVILEGES | TOKEN_IMPERSONATE,
      NULL, SecurityImpersonation, TokenImpersonation, &token);
  DWORD error = GetLastError();
  if (!had_thread_token) CloseHandle(source);
  if (ok) {
    TOKEN_PRIVILEGES privilege = {0};
    privilege.PrivilegeCount = 1;
    privilege.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
    ok = LookupPrivilegeValueW(NULL, L"SeCreateSymbolicLinkPrivilege", &privilege.Privileges[0].Luid);
    if (ok) {
      SetLastError(ERROR_SUCCESS);
      ok = AdjustTokenPrivileges(token, FALSE, &privilege, 0, NULL, NULL);
      if (GetLastError() == ERROR_NOT_ALL_ASSIGNED) { ok = FALSE; SetLastError(ERROR_PRIVILEGE_NOT_HELD); }
    }
    if (ok) ok = SetThreadToken(NULL, token);
    error = GetLastError();
    if (ok) {
      ok = DeviceIoControl(file, FSCTL_SET_REPARSE_POINT, data, size, NULL, 0, &returned, NULL);
      error = GetLastError();
      // Continuing under the temporary identity after a failed restoration is unsafe.
      if (!SetThreadToken(NULL, previous)) RaiseFailFastException(NULL, NULL, 0);
    }
  }
  if (token) CloseHandle(token);
  if (previous) CloseHandle(previous);
  SetLastError(error);
  return ok;
}
int wasmoon_windows_symlinkat(const char *target, int fd, const char *name) {
  if (!*target) { errno = ENOENT; return -1; }
  wchar_t *wide_target = wasmoon_windows_utf16(target);
  wchar_t *wide_name = wasmoon_windows_utf16(name);
  if (!wide_target || !wide_name) { free(wide_target); free(wide_name); return -1; }
  wchar_t *parent;
  if (absolute_path(name)) {
    parent = _wfullpath(NULL, wide_name, 0);
    if (parent) {
      wchar_t *last = wcsrchr(parent, L'\\');
      if (last) last[1] = 0;
    }
  } else {
    HANDLE root = wasmoon_windows_fd_handle(fd);
    DWORD length = GetFinalPathNameByHandleW(root, NULL, 0, FILE_NAME_NORMALIZED);
    parent = length ? malloc(((size_t)length + 2) * sizeof(*parent)) : NULL;
    if (parent && !GetFinalPathNameByHandleW(root, parent, length + 1, FILE_NAME_NORMALIZED)) {
      free(parent); parent = NULL;
    }
    if (parent) wcscat(parent, L"\\");
  }
  if (!parent) { free(wide_target); free(wide_name); errno = EBADF; return -1; }
  size_t query_length = wcslen(parent) + wcslen(wide_target) + 1;
  wchar_t *query = malloc(query_length * sizeof(*query));
  if (!query) { free(parent); free(wide_target); free(wide_name); errno = ENOMEM; return -1; }
  wcscpy(query, absolute_path(target) ? L"" : parent);
  wcscat(query, wide_target);
  for (wchar_t *p = query; *p; p++) if (*p == L'/') *p = L'\\';
  // Windows encodes whether a link names a directory. This query only selects
  // that attribute; the destination mutation below uses the held parent.
  DWORD attributes = GetFileAttributesW(query);
  int directory = attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY);
  DWORD target_error = GetLastError();
  free(query); free(parent);
  if (absolute_path(name)) {
    for (wchar_t *p = wide_target; *p; p++) if (*p == L'/') *p = L'\\';
    BOOL ok = CreateSymbolicLinkW(wide_name, wide_target,
        SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE | (directory ? SYMBOLIC_LINK_FLAG_DIRECTORY : 0));
    DWORD error = GetLastError(); free(wide_target); free(wide_name);
    // Report the missing target before a conflicting destination when its
    // Windows directory attribute could not be determined.
    if (!ok && attributes == INVALID_FILE_ATTRIBUTES &&
        (error == ERROR_ALREADY_EXISTS || error == ERROR_FILE_EXISTS)) error = target_error;
    return ok ? 0 : wasmoon_windows_error(error);
  }
  free(wide_name);
  // Keep the guest spelling in PrintName, while the NT substitute name uses
  // native separators and an NT namespace prefix for absolute paths.
  int absolute = absolute_path(target);
  wchar_t *substitute = absolute ? nt_absolute_name(wide_target) : _wcsdup(wide_target);
  if (!substitute) { free(wide_target); return -1; }
  for (wchar_t *p = substitute; *p; p++) if (*p == L'/') *p = L'\\';
  size_t substitute_bytes = wcslen(substitute) * sizeof(*substitute);
  size_t print_bytes = wcslen(wide_target) * sizeof(*wide_target);
  size_t bytes = substitute_bytes + print_bytes;
  if (bytes > MAXIMUM_REPARSE_DATA_BUFFER_SIZE - 20) {
    free(substitute); free(wide_target); errno = ENAMETOOLONG; return -1;
  }
  unsigned char *data = calloc(1, 20 + bytes);
  if (!data) { free(substitute); free(wide_target); errno = ENOMEM; return -1; }
  DWORD tag = IO_REPARSE_TAG_SYMLINK, flags = absolute ? 0 : 1;
  USHORT data_length = (USHORT)(12 + bytes), substitute_length = (USHORT)substitute_bytes;
  USHORT print_length = (USHORT)print_bytes;
  memcpy(data, &tag, 4); memcpy(data + 4, &data_length, 2);
  memcpy(data + 10, &substitute_length, 2); memcpy(data + 12, &substitute_length, 2);
  memcpy(data + 14, &print_length, 2); memcpy(data + 16, &flags, 4);
  memcpy(data + 20, substitute, substitute_bytes);
  memcpy(data + 20 + substitute_bytes, wide_target, print_bytes);
  free(substitute); free(wide_target);
  HANDLE handle = open_relative(fd, name, GENERIC_WRITE | DELETE, 2,
      0x00200000 | (directory ? 1 : 0x40));
  if (handle == INVALID_HANDLE_VALUE) { free(data); return -1; }
  BOOL ok = set_symlink_reparse(handle, data, (DWORD)(20 + bytes));
  DWORD error = GetLastError(); free(data);
  if (!ok) {
    FILE_DISPOSITION_INFO discard = {TRUE};
    if (!SetFileInformationByHandle(handle, FileDispositionInfo, &discard, sizeof(discard))) {
      error = GetLastError();
    }
  }
  CloseHandle(handle);
  return ok ? 0 : wasmoon_windows_error(error);
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
      CompareStringOrdinal(base_final, (int)length, target_final, (int)length, FALSE) == CSTR_EQUAL &&
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

static uint64_t filetime_ns(int64_t value) {
  return ((uint64_t)value - 116444736000000000ULL) * 100ULL;
}
static int stat_handle(HANDLE handle, wasmoon_windows_stat *stat) {
  memset(stat, 0, sizeof(*stat));
  stat->st_nlink = 1;
  SetLastError(NO_ERROR);
  DWORD kind = GetFileType(handle);
  if (kind == FILE_TYPE_UNKNOWN && GetLastError() != NO_ERROR) return wasmoon_windows_error(GetLastError());
  if (kind == FILE_TYPE_PIPE) { stat->filetype = 8; return 0; }
  if (kind == FILE_TYPE_CHAR) { stat->filetype = 2; return 0; }
  BY_HANDLE_FILE_INFORMATION info;
  FILE_BASIC_INFO times;
  if (!GetFileInformationByHandle(handle, &info) ||
      !GetFileInformationByHandleEx(handle, FileBasicInfo, &times, sizeof(times)))
    return wasmoon_windows_error(GetLastError());
  stat->st_dev = info.dwVolumeSerialNumber;
  stat->st_ino = ((uint64_t)info.nFileIndexHigh << 32) | info.nFileIndexLow;
  stat->st_nlink = info.nNumberOfLinks;
  stat->st_size = ((uint64_t)info.nFileSizeHigh << 32) | info.nFileSizeLow;
  stat->filetype = info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT ? 7 :
                   info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY ? 3 : 4;
  stat->atim_ns = filetime_ns(times.LastAccessTime.QuadPart);
  stat->mtim_ns = filetime_ns(times.LastWriteTime.QuadPart);
  stat->ctim_ns = filetime_ns(times.ChangeTime.QuadPart);
  return 0;
}
int wasmoon_windows_fstat(int fd, wasmoon_windows_stat *stat) {
  if (wasmoon_windows_is_socket(fd)) {
    if (wasmoon_windows_socket_get(fd) == INVALID_SOCKET) { errno = EBADF; return -1; }
    memset(stat, 0, sizeof(*stat)); stat->st_nlink = 1; stat->filetype = 6;
    return 0;
  }
  HANDLE handle = wasmoon_windows_fd_handle(fd);
  if (handle == INVALID_HANDLE_VALUE) return -1;
  return stat_handle(handle, stat);
}
int wasmoon_windows_ftruncate(int fd, int64_t size) {
  HANDLE handle = wasmoon_windows_fd_handle(fd);
  if (handle == INVALID_HANDLE_VALUE) return -1;
  if (size < 0 || wasmoon_windows_is_socket(fd) || GetFileType(handle) != FILE_TYPE_DISK) {
    errno = EINVAL; return -1;
  }
  FILE_END_OF_FILE_INFO information;
  information.EndOfFile.QuadPart = size;
  if (SetFileInformationByHandle(handle, FileEndOfFileInfo, &information, sizeof(information))) return 0;
  return wasmoon_windows_error(GetLastError());
}
int wasmoon_windows_fstatat(int fd, const char *path, int follow, wasmoon_windows_stat *stat) {
  HANDLE handle = open_path_or_relative(fd, path, FILE_READ_ATTRIBUTES, 1, follow ? 0 : 0x00200000);
  if (handle == INVALID_HANDLE_VALUE) return -1;
  int result = stat_handle(handle, stat), error = errno;
  CloseHandle(handle); errno = error;
  return result;
}
int wasmoon_windows_mkdirat(int fd, const char *path) {
  if (absolute_path(path)) {
    wchar_t *wide = wasmoon_windows_utf16(path);
    if (!wide) return -1;
    BOOL result = CreateDirectoryW(wide, NULL);
    DWORD error = GetLastError(); free(wide);
    return result ? 0 : wasmoon_windows_error(error);
  }
  HANDLE handle = open_relative(fd, path, FILE_READ_ATTRIBUTES, 2, 1 | 0x00200000);
  if (handle == INVALID_HANDLE_VALUE) return -1;
  CloseHandle(handle);
  return 0;
}
int wasmoon_windows_unlinkat(int fd, const char *path, int directory) {
  HANDLE handle = open_path_or_relative(fd, path, DELETE | FILE_READ_ATTRIBUTES, 1, 0x00200000);
  if (handle == INVALID_HANDLE_VALUE) return -1;
  FILE_ATTRIBUTE_TAG_INFO attributes;
  if (!GetFileInformationByHandleEx(handle, FileAttributeTagInfo, &attributes, sizeof(attributes))) {
    DWORD error = GetLastError(); CloseHandle(handle); return wasmoon_windows_error(error);
  }
  int is_directory = (attributes.FileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
  int is_link = (attributes.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0;
  size_t path_length = strlen(path);
  if (path_length && (path[path_length - 1] == '/' || path[path_length - 1] == '\\') && !is_directory) {
    CloseHandle(handle); errno = ENOTDIR; return -1;
  }
  if ((directory && (!is_directory || is_link)) || (!directory && is_directory && !is_link)) {
    CloseHandle(handle); errno = directory ? ENOTDIR : EACCES; return -1;
  }
  FILE_DISPOSITION_INFO_EX info = {FILE_DISPOSITION_FLAG_DELETE | FILE_DISPOSITION_FLAG_POSIX_SEMANTICS |
                                  FILE_DISPOSITION_FLAG_IGNORE_READONLY_ATTRIBUTE};
  BOOL result = SetFileInformationByHandle(handle, FileDispositionInfoEx, &info, sizeof(info));
  DWORD error = GetLastError(); CloseHandle(handle);
  return result ? 0 : wasmoon_windows_error(error);
}
int wasmoon_windows_renameat(int old_fd, const char *old_path, int new_fd, const char *new_path) {
  HANDLE source = open_path_or_relative(old_fd, old_path, DELETE, 1, 0x00200000);
  if (source == INVALID_HANDLE_VALUE) return -1;
  wchar_t *name = wasmoon_windows_utf16(new_path);
  if (!name) { CloseHandle(source); return -1; }
  HANDLE root = NULL;
  if (absolute_path(new_path)) {
    wchar_t *full = nt_absolute_name(name);
    free(name); name = full;
    if (!name) { CloseHandle(source); return -1; }
  } else {
    if (!*new_path || strchr(new_path, '/') || strchr(new_path, '\\') || strchr(new_path, ':') ||
        !strcmp(new_path, ".") || !strcmp(new_path, "..")) {
      free(name); CloseHandle(source); errno = EPERM; return -1;
    }
    root = wasmoon_windows_fd_handle(new_fd);
    if (root == INVALID_HANDLE_VALUE) { free(name); CloseHandle(source); return -1; }
  }
  for (wchar_t *p = name; *p; p++) if (*p == L'/') *p = L'\\';
  size_t bytes = wcslen(name) * sizeof(*name);
  // Use the NT operation so relative targets stay anchored to the held parent.
  size_t size = sizeof(FILE_RENAME_INFO) + bytes;
  FILE_RENAME_INFO *info = calloc(1, size);
  if (!info) { free(name); CloseHandle(source); errno = ENOMEM; return -1; }
  info->ReplaceIfExists = TRUE;
  info->RootDirectory = root;
  info->FileNameLength = (DWORD)bytes;
  memcpy(info->FileName, name, bytes);
  InitOnceExecuteOnce(&file_once, initialize_file_api, NULL, NULL);
  IO_STATUS_BLOCK io;
  NTSTATUS status = set_information ? set_information(source, &io, info, (ULONG)size,
      (FILE_INFORMATION_CLASS)10 /* FileRenameInformation */) : (NTSTATUS)0xC00000BB;
  BOOL result = status >= 0;
  DWORD error = result ? ERROR_SUCCESS : (status_error ? status_error(status) : ERROR_NOT_SUPPORTED);
  // Match Rust/Wasmtime's Windows rename contract: ordinary Windows rename
  // permits directory-over-file, while POSIX replacement handles empty dirs.
  // A failed POSIX retry retains the original error except for nonempty dirs.
  if (!result && error == ERROR_ACCESS_DENIED) {
    info->Flags = FILE_RENAME_FLAG_REPLACE_IF_EXISTS | FILE_RENAME_FLAG_POSIX_SEMANTICS;
    status = set_information(source, &io, info, (ULONG)size,
                             (FILE_INFORMATION_CLASS)65 /* FileRenameInformationEx */);
    result = status >= 0;
    if (!result && status_error(status) == ERROR_DIR_NOT_EMPTY) error = ERROR_DIR_NOT_EMPTY;
  }
  free(name); free(info); CloseHandle(source);
  return result ? 0 : wasmoon_windows_error(error);
}
int wasmoon_windows_linkat(int old_fd, const char *old_path, int new_fd, const char *new_path, int follow) {
  size_t new_length = strlen(new_path);
  if (new_length && (new_path[new_length - 1] == '/' || new_path[new_length - 1] == '\\')) {
    errno = ENOENT; return -1;
  }
  HANDLE source = open_path_or_relative(old_fd, old_path, FILE_READ_ATTRIBUTES, 1,
                                        follow ? 0 : 0x00200000);
  if (source == INVALID_HANDLE_VALUE) return -1;
  wasmoon_windows_stat stat = {0};
  if (stat_handle(source, &stat) < 0 || stat.filetype == 3) {
    int error = stat.filetype == 3 ? EPERM : errno;
    CloseHandle(source); errno = error; return -1;
  }
  HANDLE root = NULL;
  wchar_t *name = wasmoon_windows_utf16(new_path);
  if (!name) { CloseHandle(source); return -1; }
  if (absolute_path(new_path)) {
    wchar_t *full = nt_absolute_name(name);
    free(name); name = full;
    if (!name) { CloseHandle(source); return -1; }
  } else {
    if (!*new_path || strchr(new_path, '/') || strchr(new_path, '\\') || strchr(new_path, ':') ||
        !strcmp(new_path, ".") || !strcmp(new_path, "..")) {
      free(name); CloseHandle(source); errno = EPERM; return -1;
    }
    root = wasmoon_windows_fd_handle(new_fd);
    if (root == INVALID_HANDLE_VALUE) { free(name); CloseHandle(source); return -1; }
  }
  // FILE_LINK_INFORMATION shares the documented layout of FILE_RENAME_INFO.
  size_t bytes = wcslen(name) * sizeof(*name);
  size_t size = sizeof(FILE_RENAME_INFO) + bytes;
  FILE_RENAME_INFO *info = calloc(1, size);
  if (!info) { free(name); CloseHandle(source); errno = ENOMEM; return -1; }
  info->RootDirectory = root;
  info->FileNameLength = (DWORD)bytes;
  memcpy(info->FileName, name, bytes);
  InitOnceExecuteOnce(&file_once, initialize_file_api, NULL, NULL);
  IO_STATUS_BLOCK io;
  NTSTATUS result = set_information ? set_information(source, &io, info, (ULONG)size,
      (FILE_INFORMATION_CLASS)11 /* FileLinkInformation */) : (NTSTATUS)0xC00000BB;
  free(info); free(name); CloseHandle(source);
  if (result >= 0) return 0;
  return wasmoon_windows_error(status_error ? status_error(result) : ERROR_NOT_SUPPORTED);
}
static int set_times(HANDLE handle, int64_t atim, int64_t mtim, int flags) {
  FILETIME access, modified, now;
  FILETIME *access_ptr = NULL, *modified_ptr = NULL;
  GetSystemTimePreciseAsFileTime(&now);
  if (flags & 1) {
    ULARGE_INTEGER ticks; ticks.QuadPart = (uint64_t)atim / 100 + 116444736000000000ULL;
    access.dwLowDateTime = ticks.LowPart; access.dwHighDateTime = ticks.HighPart;
    access_ptr = &access;
  } else if (flags & 2) access_ptr = &now;
  if (flags & 4) {
    ULARGE_INTEGER ticks; ticks.QuadPart = (uint64_t)mtim / 100 + 116444736000000000ULL;
    modified.dwLowDateTime = ticks.LowPart; modified.dwHighDateTime = ticks.HighPart;
    modified_ptr = &modified;
  } else if (flags & 8) modified_ptr = &now;
  if (SetFileTime(handle, NULL, access_ptr, modified_ptr)) return 0;
  return wasmoon_windows_error(GetLastError());
}
int wasmoon_windows_futimens(int fd, int64_t atim, int64_t mtim, int flags) {
  HANDLE handle = wasmoon_windows_fd_handle(fd);
  if (handle == INVALID_HANDLE_VALUE) return -1;
  return set_times(handle, atim, mtim, flags);
}
int wasmoon_windows_utimensat(int fd, const char *path, int64_t atim, int64_t mtim, int flags, int follow) {
  HANDLE handle = open_path_or_relative(fd, path, FILE_WRITE_ATTRIBUTES, 1, follow ? 0 : 0x00200000);
  if (handle == INVALID_HANDLE_VALUE) return -1;
  int result = set_times(handle, atim, mtim, flags), error = errno;
  CloseHandle(handle); errno = error;
  return result;
}
#endif
