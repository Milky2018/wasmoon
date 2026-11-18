#include <errno.h>
#include <stdint.h>
#include <limits.h>
#include "moonbit.h"
#ifdef _WIN32
#include "../windows_io.h"
#else
#include <sys/socket.h>
#include <sys/uio.h>
#endif

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_kind(int fd) {
  int kind = 0;
#ifdef _WIN32
  if (!wasmoon_windows_is_socket(fd)) {
    if (wasmoon_windows_fd_handle(fd) != INVALID_HANDLE_VALUE) errno = ENOTSOCK;
    return -1;
  }
  SOCKET socket = wasmoon_windows_socket_get(fd);
  if (socket == INVALID_SOCKET) return -1;
  int length = sizeof(kind);
  if (getsockopt(socket, SOL_SOCKET, SO_TYPE, (char *)&kind, &length))
    return wasmoon_windows_socket_error(WSAGetLastError());
#else
  socklen_t length = sizeof(kind);
  if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &kind, &length)) return -1;
#endif
  if (kind == SOCK_STREAM) return 1;
  if (kind == SOCK_DGRAM) return 2;
  errno = ENOTSUP; return -1;
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_p1_recv(int fd, unsigned char *buffer,
    int length, int flags, int *truncated) {
  if (length < 0) { errno = EINVAL; return -1; }
  int native_flags = (flags & 1 ? MSG_PEEK : 0) | (flags & 2 ? MSG_WAITALL : 0);
  *truncated = 0;
#ifdef _WIN32
  SOCKET socket = wasmoon_windows_socket_get(fd);
  if (socket == INVALID_SOCKET) return -1;
  WSABUF data = {(ULONG)length, (char *)buffer};
  DWORD received = 0, receive_flags = (DWORD)native_flags;
  int result = WSARecv(socket, &data, 1, &received, &receive_flags, NULL, NULL);
  if (result == SOCKET_ERROR) {
    int error = WSAGetLastError();
    if (error != WSAEMSGSIZE) return wasmoon_windows_socket_error(error);
    *truncated = 1;
  }
  return (int)received;
#else
  struct iovec data = {buffer, (size_t)length};
  struct msghdr message = {0};
  message.msg_iov = &data;
  message.msg_iovlen = 1;
  ssize_t received = recvmsg(fd, &message, native_flags);
  if (received < 0) return -1;
  *truncated = (message.msg_flags & MSG_TRUNC) != 0;
  return (int)received;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_p1_send(int fd, const unsigned char *buffer, int length) {
  if (length < 0) { errno = EINVAL; return -1; }
#ifdef _WIN32
  SOCKET socket = wasmoon_windows_socket_get(fd);
  if (socket == INVALID_SOCKET) return -1;
  int sent = send(socket, (const char *)buffer, length, 0);
  return sent == SOCKET_ERROR ? wasmoon_windows_socket_error(WSAGetLastError()) : sent;
#else
  int flags = 0;
#ifdef MSG_NOSIGNAL
  flags |= MSG_NOSIGNAL;
#elif defined(SO_NOSIGPIPE)
  int enabled = 1;
  if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled))) return -1;
#endif
  return (int)send(fd, buffer, (size_t)length, flags);
#endif
}
