#ifdef _WIN32
#include "windows_io.h"
#include <errno.h>
#include <io.h>
#include <stdlib.h>
#pragma comment(lib, "ws2_32.lib")

// CRT descriptors are int-sized; SOCKET is pointer-sized. Never truncate one
// into the other. Reserved ids hold sockets until explicit close, with reuse
// following ordinary descriptor semantics. Callers must not close a borrowed
// descriptor concurrently with an operation on it.
#define SOCKET_FD_BASE 0x40000000
static SRWLOCK sockets_lock = SRWLOCK_INIT;
static SOCKET *sockets;
static size_t sockets_count;
static INIT_ONCE winsock_once = INIT_ONCE_STATIC_INIT;
static int winsock_error;
static BOOL CALLBACK initialize_winsock(PINIT_ONCE once, PVOID arg, PVOID *context) {
    (void)once; (void)arg; (void)context;
    WSADATA data;
    winsock_error = WSAStartup(MAKEWORD(2, 2), &data);
    return TRUE;
}
int wasmoon_windows_winsock_init(void) {
    InitOnceExecuteOnce(&winsock_once, initialize_winsock, NULL, NULL);
    if (winsock_error) { errno = EIO; return -1; }
    return 0;
}
int wasmoon_windows_socket_adopt(SOCKET socket) {
    if (socket == INVALID_SOCKET) return -1;
    AcquireSRWLockExclusive(&sockets_lock);
    size_t slot = 0;
    while (slot < sockets_count && sockets[slot] != INVALID_SOCKET) slot++;
    if (slot == sockets_count) {
        if (sockets_count >= 0x3fffffff) {
            ReleaseSRWLockExclusive(&sockets_lock);
            closesocket(socket); errno = EMFILE; return -1;
        }
        size_t count = sockets_count ? sockets_count * 2 : 16;
        if (count > 0x3fffffff) count = 0x3fffffff;
        SOCKET *next = realloc(sockets, count * sizeof(*next));
        if (!next) {
            ReleaseSRWLockExclusive(&sockets_lock);
            closesocket(socket); errno = ENOMEM; return -1;
        }
        for (size_t i = sockets_count; i < count; i++) next[i] = INVALID_SOCKET;
        sockets = next;
        sockets_count = count;
    }
    sockets[slot] = socket;
    ReleaseSRWLockExclusive(&sockets_lock);
    return SOCKET_FD_BASE + (int)slot;
}
SOCKET wasmoon_windows_socket_get(int fd) {
    SOCKET socket = INVALID_SOCKET;
    if (fd >= SOCKET_FD_BASE) {
        size_t slot = (size_t)(fd - SOCKET_FD_BASE);
        AcquireSRWLockShared(&sockets_lock);
        if (slot < sockets_count) socket = sockets[slot];
        ReleaseSRWLockShared(&sockets_lock);
    }
    if (socket == INVALID_SOCKET) errno = ENOTSOCK;
    return socket;
}
int wasmoon_windows_is_socket(int fd) {
    return fd >= SOCKET_FD_BASE;
}
static void ignore_invalid_descriptor(const wchar_t *expression, const wchar_t *function,
                                      const wchar_t *file, unsigned line, uintptr_t reserved) {
    (void)expression; (void)function; (void)file; (void)line; (void)reserved;
}
HANDLE wasmoon_windows_fd_handle(int fd) {
    if (wasmoon_windows_is_socket(fd)) return (HANDLE)wasmoon_windows_socket_get(fd);
    if (fd < 0) { errno = EBADF; return INVALID_HANDLE_VALUE; }
    // UCRT otherwise terminates the process for an invalid inherited fd.
    _invalid_parameter_handler old = _set_thread_local_invalid_parameter_handler(ignore_invalid_descriptor);
    intptr_t handle = _get_osfhandle(fd);
    _set_thread_local_invalid_parameter_handler(old);
    return (HANDLE)handle;
}
int wasmoon_windows_close(int fd) {
    if (!wasmoon_windows_is_socket(fd)) return _close(fd);
    size_t slot = (size_t)(fd - SOCKET_FD_BASE);
    AcquireSRWLockExclusive(&sockets_lock);
    SOCKET socket = slot < sockets_count ? sockets[slot] : INVALID_SOCKET;
    if (socket != INVALID_SOCKET) sockets[slot] = INVALID_SOCKET;
    ReleaseSRWLockExclusive(&sockets_lock);
    if (socket == INVALID_SOCKET) { errno = EBADF; return -1; }
    int result = closesocket(socket);
    return result == SOCKET_ERROR ? wasmoon_windows_socket_error(WSAGetLastError()) : 0;
}
int wasmoon_windows_socket_error(int error) {
    switch (error) {
        case WSAEWOULDBLOCK: errno = EAGAIN; break;
        case WSAEINTR: errno = EINTR; break;
        case WSAEBADF: case WSAENOTSOCK: errno = EBADF; break;
        case WSAEACCES: errno = EACCES; break;
        case WSAEINVAL: errno = EINVAL; break;
        case WSAEADDRINUSE: errno = EADDRINUSE; break;
        case WSAEADDRNOTAVAIL: errno = EADDRNOTAVAIL; break;
        case WSAECONNRESET: errno = ECONNRESET; break;
        case WSAECONNREFUSED: errno = ECONNREFUSED; break;
        case WSAECONNABORTED: errno = ECONNABORTED; break;
        case WSAENOTCONN: errno = ENOTCONN; break;
        case WSAETIMEDOUT: errno = ETIMEDOUT; break;
        case WSAEINPROGRESS: errno = EINPROGRESS; break;
        case WSAENOBUFS: errno = ENOMEM; break;
        case WSAEAFNOSUPPORT: errno = EAFNOSUPPORT; break;
        case WSAEMSGSIZE: errno = EMSGSIZE; break;
        case WSAESHUTDOWN: errno = EPIPE; break;
        default: errno = EIO; break;
    }
    return -1;
}
#endif
