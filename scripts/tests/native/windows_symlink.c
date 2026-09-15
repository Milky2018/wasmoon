// Test-only token and scheduling controls for the public symlink primitive.
#include <windows.h>
#include <stdint.h>
static HANDLE previous;
static BOOL had_previous;
static void (*locked_hook)(void);
__declspec(dllexport) void wasmoon_test_symlink_hook(void (*hook)(void)) { locked_hook = hook; }
void wasmoon_symlink_locked_hook(void) { if (locked_hook) locked_hook(); }
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
