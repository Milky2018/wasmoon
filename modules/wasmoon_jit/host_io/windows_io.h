// Windows descriptor ownership shared by the WASI interpreter and native host.
#ifndef WASMOON_WINDOWS_IO_H
#define WASMOON_WINDOWS_IO_H
#include "moonbit.h"
MOONBIT_FFI_EXPORT int wasmoon_host_claim_input(int fd);
MOONBIT_FFI_EXPORT void wasmoon_host_release_input(int fd);
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <windows.h>
#include <stdint.h>
#define WASMOON_O_NONBLOCK 0x04000000
int wasmoon_windows_notification_pipe(int *fds);
int wasmoon_windows_track_file(int fd, int flags);
int wasmoon_windows_getfl(int fd);
int wasmoon_windows_setfl(int fd, int flags);
int wasmoon_windows_error(DWORD error);
int wasmoon_windows_read(int fd, void *buffer, int count);
int wasmoon_windows_write(int fd, const void *buffer, int count);
int wasmoon_windows_pread(int fd, void *buffer, int count, int64_t offset);
int wasmoon_windows_pwrite(int fd, const void *buffer, int count, int64_t offset);
int wasmoon_windows_winsock_init(void);
int wasmoon_windows_socket_adopt(SOCKET socket, int flags);
SOCKET wasmoon_windows_socket_get(int fd);
int wasmoon_windows_is_socket(int fd);
HANDLE wasmoon_windows_fd_handle(int fd);
int wasmoon_windows_close(int fd);
int wasmoon_windows_dup(int fd);
int wasmoon_windows_dup2(int old_fd, int new_fd);
int wasmoon_windows_socket_error(int error);
int64_t wasmoon_windows_bytes_available(int fd);
int wasmoon_windows_poll_interruptible(const int *fds, const int *events, int *revents,
                         int count, int timeout_ms, SOCKET wake, int *woken);
int wasmoon_windows_poll(const int *fds, const int *events, int *revents,
                         int count, int timeout_ms);
#endif
#endif
