// Windows descriptor ownership shared by the WASI interpreter and native host.
#ifndef WASMOON_WINDOWS_IO_H
#define WASMOON_WINDOWS_IO_H
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <windows.h>
#include <stdint.h>
int wasmoon_windows_winsock_init(void);
int wasmoon_windows_socket_adopt(SOCKET socket);
SOCKET wasmoon_windows_socket_get(int fd);
int wasmoon_windows_is_socket(int fd);
HANDLE wasmoon_windows_fd_handle(int fd);
int wasmoon_windows_close(int fd);
int wasmoon_windows_socket_error(int error);
#endif
#endif
