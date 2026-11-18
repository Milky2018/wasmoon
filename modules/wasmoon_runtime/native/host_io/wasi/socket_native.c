// Native networking backend; no guest memory or WASI policy lives here.
#include "moonbit.h"
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include "../windows_io.h"
#include <fcntl.h>
#include <ws2tcpip.h>
#include <mstcpip.h>
#include <process.h>
typedef int socklen_t;
#else
#include <unistd.h>
#include <fcntl.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#endif

static int wasmoon_wasi_socket_family(int family) {
  return family == 4 ? AF_INET : family == 6 ? AF_INET6 : -1;
}

static int wasmoon_wasi_socket_address(
  int family,
  const uint8_t *address,
  int port,
  int scope_id,
  struct sockaddr_storage *storage,
  socklen_t *length
) {
  memset(storage, 0, sizeof(*storage));
  if (family == 4) {
    struct sockaddr_in *addr = (struct sockaddr_in *)storage;
    addr->sin_family = AF_INET;
    addr->sin_port = htons((uint16_t)port);
    memcpy(&addr->sin_addr, address, 4);
    *length = sizeof(*addr);
    return 1;
  }
  if (family == 6) {
    struct sockaddr_in6 *addr = (struct sockaddr_in6 *)storage;
    addr->sin6_family = AF_INET6;
    addr->sin6_port = htons((uint16_t)port);
    addr->sin6_scope_id = (uint32_t)scope_id;
    memcpy(&addr->sin6_addr, address, 16);
    *length = sizeof(*addr);
    return 1;
  }
  errno = EAFNOSUPPORT;
  return 0;
}

static int wasmoon_wasi_decode_socket_address(
  const struct sockaddr_storage *storage,
  socklen_t length,
  uint8_t *family,
  uint8_t *address,
  uint16_t *port,
  uint32_t *scope_id
) {
  memset(address, 0, 16);
  if (length >= (socklen_t)sizeof(struct sockaddr_in) && storage->ss_family == AF_INET) {
    const struct sockaddr_in *addr = (const struct sockaddr_in *)storage;
    *family = 4;
    *port = ntohs(addr->sin_port);
    *scope_id = 0;
    memcpy(address, &addr->sin_addr, 4);
    return 0;
  }
  if (length >= (socklen_t)sizeof(struct sockaddr_in6) && storage->ss_family == AF_INET6) {
    const struct sockaddr_in6 *addr = (const struct sockaddr_in6 *)storage;
    *family = 6;
    *port = ntohs(addr->sin6_port);
    *scope_id = addr->sin6_scope_id;
    memcpy(address, &addr->sin6_addr, 16);
    return 0;
  }
  errno = EAFNOSUPPORT;
  return -1;
}

static int64_t wasmoon_wasi_socket_result(int64_t result) {
#ifdef _WIN32
  if (result == SOCKET_ERROR) return wasmoon_windows_socket_error(WSAGetLastError());
#endif
  return result;
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_create(int family, int kind) {
#ifdef _WIN32
  int native_family = wasmoon_wasi_socket_family(family);
  if (native_family < 0 || (kind != 1 && kind != 2)) { errno = EAFNOSUPPORT; return -1; }
  if (wasmoon_windows_winsock_init()) return -1;
  SOCKET socket = WSASocketW(native_family, kind == 1 ? SOCK_STREAM : SOCK_DGRAM,
                            0, NULL, 0, WSA_FLAG_NO_HANDLE_INHERIT);
  if (socket == INVALID_SOCKET) return wasmoon_windows_socket_error(WSAGetLastError());
  u_long nonblocking = 1;
  int enabled = 1;
  if (ioctlsocket(socket, FIONBIO, &nonblocking) ||
      (native_family == AF_INET6 && setsockopt(socket, IPPROTO_IPV6, IPV6_V6ONLY,
                                             (const char *)&enabled, sizeof(enabled)))) {
    int error = WSAGetLastError();
    closesocket(socket);
    return wasmoon_windows_socket_error(error);
  }
  return wasmoon_windows_socket_adopt(socket, _O_RDWR | WASMOON_O_NONBLOCK);
#else
  int native_family = wasmoon_wasi_socket_family(family);
  if (native_family < 0 || (kind != 1 && kind != 2)) {
    errno = EAFNOSUPPORT;
    return -1;
  }
  int fd = socket(native_family, kind == 1 ? SOCK_STREAM : SOCK_DGRAM, 0);
  if (fd < 0) return -1;
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) {
    close(fd);
    return -1;
  }
  if (native_family == AF_INET6) {
    int enabled = 1;
    if (setsockopt(
      fd,
      IPPROTO_IPV6,
      IPV6_V6ONLY,
      &enabled,
      sizeof(enabled)
    ) != 0) {
      close(fd);
      return -1;
    }
  }
  if (kind == 1) {
    int enabled = 1;
    if (setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof(enabled)) != 0) {
      int error = errno;
      close(fd);
      errno = error;
      return -1;
    }
  }
  return fd;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_bind(
  int fd,
  int family,
  moonbit_bytes_t address,
  int port,
  int scope_id
) {
#ifdef _WIN32
  SOCKET socket = wasmoon_windows_socket_get(fd);
  if (socket == INVALID_SOCKET) return -1;
#else
  int socket = fd;
#endif
  struct sockaddr_storage storage;
  socklen_t length;
  if (!wasmoon_wasi_socket_address(family, address, port, scope_id, &storage, &length)) return -1;
  return (int)wasmoon_wasi_socket_result(bind(socket, (struct sockaddr *)&storage, length));
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_connect(
  int fd,
  int family,
  moonbit_bytes_t address,
  int port,
  int scope_id
) {
#ifdef _WIN32
  SOCKET socket = wasmoon_windows_socket_get(fd);
  if (socket == INVALID_SOCKET) return -1;
#else
  int socket = fd;
#endif
  struct sockaddr_storage storage;
  socklen_t length;
  if (!wasmoon_wasi_socket_address(family, address, port, scope_id, &storage, &length)) return -1;
  if (connect(socket, (struct sockaddr *)&storage, length) == 0) return 0;
#ifdef _WIN32
  int error = WSAGetLastError();
  if (error == WSAEWOULDBLOCK || error == WSAEINPROGRESS) return 1;
  return wasmoon_windows_socket_error(error);
#else
  if (errno == EINPROGRESS || errno == EWOULDBLOCK) return 1;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_disconnect(int fd) {
#ifdef _WIN32
  SOCKET socket = wasmoon_windows_socket_get(fd);
  if (socket == INVALID_SOCKET) return -1;
#else
  int socket = fd;
#endif
  struct sockaddr_storage storage;
  memset(&storage, 0, sizeof(storage));
  storage.ss_family = AF_UNSPEC;
  int result = connect(socket, (struct sockaddr *)&storage, sizeof(storage));
#ifdef __APPLE__
  // Darwin disconnects the datagram socket before rejecting AF_UNSPEC.
  // Confirm the resulting state instead of treating any EINVAL as success.
  if (result < 0 && (errno == EAFNOSUPPORT || errno == EINVAL)) {
    int saved = errno;
    socklen_t length = sizeof(storage);
    if (getpeername(socket, (struct sockaddr *)&storage, &length) < 0 &&
        errno == ENOTCONN) return 0;
    errno = saved;
  }
#endif
  return (int)wasmoon_wasi_socket_result(result);
}

MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_socket_recv_from(
  int fd,
  moonbit_bytes_t data,
  int length,
  uint8_t *family,
  uint8_t *address,
  uint16_t *port,
  uint32_t *scope_id
) {
#ifdef _WIN32
  SOCKET socket = wasmoon_windows_socket_get(fd);
  if (socket == INVALID_SOCKET) return -1;
#else
  int socket = fd;
#endif
  struct sockaddr_storage storage;
  socklen_t storage_length = sizeof(storage);
  int64_t received = recvfrom(
    socket, (char *)data, length, 0, (struct sockaddr *)&storage, &storage_length
  );
  if (received < 0) return wasmoon_wasi_socket_result(received);
  return wasmoon_wasi_decode_socket_address(&storage, storage_length, family, address, port, scope_id)
    == 0 ? received : -1;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_socket_send_to(
  int fd,
  moonbit_bytes_t data,
  int length,
  int has_address,
  int family,
  moonbit_bytes_t address,
  int port,
  int scope_id
) {
#ifdef _WIN32
  SOCKET socket = wasmoon_windows_socket_get(fd);
  if (socket == INVALID_SOCKET) return -1;
#else
  int socket = fd;
#endif
  if (!has_address) return wasmoon_wasi_socket_result(send(socket, (const char *)data, length, 0));
  struct sockaddr_storage storage;
  socklen_t address_length;
  if (!wasmoon_wasi_socket_address(family, address, port, scope_id, &storage, &address_length)) return -1;
  return wasmoon_wasi_socket_result(sendto(
    socket, (const char *)data, length, 0, (struct sockaddr *)&storage, address_length
  ));
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_listen(int fd, int backlog) {
#ifdef _WIN32
  SOCKET socket = wasmoon_windows_socket_get(fd);
  if (socket == INVALID_SOCKET) return -1;
  int result = listen(socket, backlog);
  return result == SOCKET_ERROR ? wasmoon_windows_socket_error(WSAGetLastError()) : result;
#else
  return listen(fd, backlog);
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_error(int fd) {
#ifdef _WIN32
  SOCKET socket = wasmoon_windows_socket_get(fd);
  if (socket == INVALID_SOCKET) return -1;
  int error = 0;
  int length = sizeof(error);
  if (getsockopt(socket, SOL_SOCKET, SO_ERROR, (char *)&error, &length))
    return wasmoon_windows_socket_error(WSAGetLastError());
  if (!error) return 0;
  wasmoon_windows_socket_error(error);
  return errno;
#else
  int error = 0;
  socklen_t length = sizeof(error);
  if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) != 0) return -1;
  return error;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_address_get(
  int fd,
  int peer,
  uint8_t *family,
  uint8_t *address,
  uint16_t *port,
  uint32_t *scope_id
) {
#ifdef _WIN32
  SOCKET socket = wasmoon_windows_socket_get(fd);
  if (socket == INVALID_SOCKET) return -1;
#else
  int socket = fd;
#endif
  struct sockaddr_storage storage;
  socklen_t length = sizeof(storage);
  int result = peer
    ? getpeername(socket, (struct sockaddr *)&storage, &length)
    : getsockname(socket, (struct sockaddr *)&storage, &length);
  if (result != 0) return (int)wasmoon_wasi_socket_result(-1);
  return wasmoon_wasi_decode_socket_address(&storage, length, family, address, port, scope_id);
}

static int wasmoon_wasi_native_socket_option(
  int family, int option, int *level, int *native_option
) {
  *level = SOL_SOCKET;
  switch (option) {
    case 0: *native_option = SO_KEEPALIVE; break;
    case 1:
      *level = IPPROTO_TCP;
#if defined(__APPLE__)
      *native_option = TCP_KEEPALIVE;
#else
      *native_option = TCP_KEEPIDLE;
#endif
      break;
    case 2: *level = IPPROTO_TCP; *native_option = TCP_KEEPINTVL; break;
    case 3: *level = IPPROTO_TCP; *native_option = TCP_KEEPCNT; break;
    case 4:
      *level = family == 6 ? IPPROTO_IPV6 : IPPROTO_IP;
      *native_option = family == 6 ? IPV6_UNICAST_HOPS : IP_TTL;
      break;
    case 5: *native_option = SO_RCVBUF; break;
    case 6: *native_option = SO_SNDBUF; break;
    case 7: *native_option = SO_REUSEADDR; break;
    default: errno = EINVAL; return 0;
  }
  return 1;
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_option_get(
  int fd,
  int family,
  int option
) {
#ifdef _WIN32
  SOCKET socket = wasmoon_windows_socket_get(fd);
  if (socket == INVALID_SOCKET) return -1;
#else
  int socket = fd;
#endif
  int level, native_option;
  if (!wasmoon_wasi_native_socket_option(family, option, &level, &native_option)) return -1;
  int value = 0;
  socklen_t length = sizeof(value);
  if (getsockopt(socket, level, native_option, (char *)&value, &length) != 0)
    return (int)wasmoon_wasi_socket_result(-1);
#ifdef __linux__
  // Linux includes doubled bookkeeping space in the returned buffer size.
  // Expose the same application units accepted by setsockopt, as Wasmtime does.
  if (option == 5 || option == 6) value /= 2;
#endif
  return value;
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_socket_option_set(
  int fd,
  int family,
  int option,
  int value
) {
#ifdef _WIN32
  SOCKET socket = wasmoon_windows_socket_get(fd);
  if (socket == INVALID_SOCKET) return -1;
#else
  int socket = fd;
#endif
  int level, native_option;
  if (!wasmoon_wasi_native_socket_option(family, option, &level, &native_option)) return -1;
  return (int)wasmoon_wasi_socket_result(
    setsockopt(socket, level, native_option, (const char *)&value, sizeof(value))
  );
}

MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_socket_bytes_available(int fd) {
#ifdef _WIN32
  return wasmoon_windows_bytes_available(fd);
#else
  int available = 0;
  if (ioctl(fd, FIONREAD, &available) != 0) return -1;
  return (int64_t)available;
#endif
}

// Socket shutdown
MOONBIT_FFI_EXPORT int wasmoon_wasi_shutdown(int sockfd, int how) {
#ifdef _WIN32
  SOCKET socket = wasmoon_windows_socket_get(sockfd);
  if (socket == INVALID_SOCKET) return -1;
  int result = shutdown(socket, how);
  return result == SOCKET_ERROR ? wasmoon_windows_socket_error(WSAGetLastError()) : result;
#else
  return shutdown(sockfd, how);
#endif
}

// Socket accept
MOONBIT_FFI_EXPORT int wasmoon_wasi_accept(int sockfd) {
#ifdef _WIN32
  SOCKET listener = wasmoon_windows_socket_get(sockfd);
  if (listener == INVALID_SOCKET) return -1;
  SOCKET socket = accept(listener, NULL, NULL);
  if (socket == INVALID_SOCKET) return wasmoon_windows_socket_error(WSAGetLastError());
  u_long nonblocking = 1;
  if (ioctlsocket(socket, FIONBIO, &nonblocking)) {
    int error = WSAGetLastError();
    closesocket(socket);
    return wasmoon_windows_socket_error(error);
  }
  return wasmoon_windows_socket_adopt(socket, _O_RDWR | WASMOON_O_NONBLOCK);
#else
  int fd = accept(sockfd, NULL, NULL);
  if (fd < 0) return -1;
  int flags = fcntl(fd, F_GETFL, 0);
  if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) {
    close(fd);
    return -1;
  }
  return fd;
#endif
}

// Raise a signal
