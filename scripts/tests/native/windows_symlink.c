// Test-only token and scheduling controls for the public symlink primitive.
#include <windows.h>
#include <stdint.h>
#include <winioctl.h>
#include <string.h>
static HANDLE previous;
static BOOL had_previous;
__declspec(dllexport) int wasmoon_test_remove_symlink_privilege(void) {
  HANDLE source = NULL, token = NULL;
  had_previous = OpenThreadToken(GetCurrentThread(), TOKEN_QUERY | TOKEN_DUPLICATE | TOKEN_IMPERSONATE,
      TRUE, &previous);
  if (had_previous) source = previous;
  else if (GetLastError() != ERROR_NO_TOKEN ||
      !OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY | TOKEN_DUPLICATE, &source)) return 0;
  BOOL ok = DuplicateTokenEx(source, TOKEN_QUERY | TOKEN_ADJUST_PRIVILEGES | TOKEN_IMPERSONATE,
      NULL, SecurityImpersonation, TokenImpersonation, &token);
  if (!had_previous) CloseHandle(source);
  if (ok) {
    TOKEN_PRIVILEGES privileges = {0};
    privileges.PrivilegeCount = 1;
    privileges.Privileges[0].Attributes = SE_PRIVILEGE_REMOVED;
    ok = LookupPrivilegeValueW(NULL, L"SeCreateSymbolicLinkPrivilege", &privileges.Privileges[0].Luid);
    if (ok) ok = AdjustTokenPrivileges(token, FALSE, &privileges, 0, NULL, NULL);
    if (ok) ok = SetThreadToken(NULL, token);
  }
  if (token) CloseHandle(token);
  if (!ok && had_previous) CloseHandle(previous);
  return ok;
}
__declspec(dllexport) int wasmoon_test_restore_token(void) {
  BOOL ok = SetThreadToken(NULL, had_previous ? previous : NULL);
  if (had_previous) CloseHandle(previous);
  previous = NULL;
  return ok;
}

__declspec(dllexport) int wasmoon_test_has_symlink_privilege(void) {
  HANDLE token;
  if (!OpenThreadToken(GetCurrentThread(), TOKEN_QUERY, TRUE, &token)) return -1;
  DWORD size = 0;
  GetTokenInformation(token, TokenPrivileges, NULL, 0, &size);
  TOKEN_PRIVILEGES *privileges = (TOKEN_PRIVILEGES *)HeapAlloc(GetProcessHeap(), 0, size);
  LUID luid;
  int result = -1;
  if (privileges && LookupPrivilegeValueW(NULL, L"SeCreateSymbolicLinkPrivilege", &luid) &&
      GetTokenInformation(token, TokenPrivileges, privileges, size, &size)) {
    result = 0;
    for (DWORD i = 0; i < privileges->PrivilegeCount; i++) {
      LUID entry = privileges->Privileges[i].Luid;
      if (entry.LowPart == luid.LowPart && entry.HighPart == luid.HighPart) result = 1;
    }
  }
  if (privileges) HeapFree(GetProcessHeap(), 0, privileges);
  CloseHandle(token);
  return result;
}
// Independent OS control: set a relative symlink reparse buffer directly, without
// CreateSymbolicLinkW, privilege adjustment, or any Wasmoon code.
__declspec(dllexport) DWORD wasmoon_test_raw_symlink(const wchar_t *path) {
  HANDLE file = CreateFileW(path, GENERIC_WRITE | DELETE,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, CREATE_NEW, 0, NULL);
  if (file == INVALID_HANDLE_VALUE) return GetLastError();
  unsigned char data[48] = {0};
  DWORD tag = IO_REPARSE_TAG_SYMLINK, flags = 1, returned;
  USHORT length = 40, name_length = 14;
  memcpy(data, &tag, 4); memcpy(data + 4, &length, 2);
  memcpy(data + 10, &name_length, 2); memcpy(data + 12, &name_length, 2);
  memcpy(data + 14, &name_length, 2); memcpy(data + 16, &flags, 4);
  memcpy(data + 20, L"missing", 14); memcpy(data + 34, L"missing", 14);
  BOOL ok = DeviceIoControl(file, FSCTL_SET_REPARSE_POINT, data, sizeof(data), NULL, 0, &returned, NULL);
  DWORD error = ok ? 0 : GetLastError();
  FILE_DISPOSITION_INFO discard = {TRUE};
  if (!SetFileInformationByHandle(file, FileDispositionInfo, &discard, sizeof(discard))) error = GetLastError();
  CloseHandle(file);
  return error;
}
