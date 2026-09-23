// Native networking backend; no guest memory or WASI policy lives here.
#include "moonbit.h"
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include "../windows_io.h"
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

struct wasmoon_wasi_resolver_address {
  uint8_t family;
  uint8_t address[16];
  uint32_t scope_id;
};

struct wasmoon_wasi_resolver {
#ifdef _WIN32
  SRWLOCK mutex;
#else
  pthread_mutex_t mutex;
#endif
  int read_fd;
  int write_fd;
  int completed;
  int dropped;
  int gai_error;
  size_t count;
  size_t index;
  struct wasmoon_wasi_resolver_address *addresses;
  char *name;
};

static void wasmoon_wasi_resolver_lock(struct wasmoon_wasi_resolver *resolver) {
#ifdef _WIN32
  AcquireSRWLockExclusive(&resolver->mutex);
#else
  pthread_mutex_lock(&resolver->mutex);
#endif
}
static void wasmoon_wasi_resolver_unlock(struct wasmoon_wasi_resolver *resolver) {
#ifdef _WIN32
  ReleaseSRWLockExclusive(&resolver->mutex);
#else
  pthread_mutex_unlock(&resolver->mutex);
#endif
}
static void wasmoon_wasi_resolver_close(int fd) {
#ifdef _WIN32
  wasmoon_windows_close(fd);
#else
  close(fd);
#endif
}

static void wasmoon_wasi_resolver_free(struct wasmoon_wasi_resolver *resolver) {
  if (resolver->read_fd >= 0) wasmoon_wasi_resolver_close(resolver->read_fd);
  if (resolver->write_fd >= 0) wasmoon_wasi_resolver_close(resolver->write_fd);
  free(resolver->addresses);
  free(resolver->name);
#ifndef _WIN32
  pthread_mutex_destroy(&resolver->mutex);
#endif
  free(resolver);
}

static int wasmoon_wasi_is_mapped_ipv4(const struct in6_addr *address) {
  const uint8_t *bytes = (const uint8_t *)address;
  for (int i = 0; i < 10; i++) {
    if (bytes[i] != 0) return 0;
  }
  return bytes[10] == 0xff && bytes[11] == 0xff;
}

#ifdef _WIN32
static unsigned __stdcall wasmoon_wasi_resolver_run(void *argument) {
#else
static void *wasmoon_wasi_resolver_run(void *argument) {
#endif
  struct wasmoon_wasi_resolver *resolver =
    (struct wasmoon_wasi_resolver *)argument;
  struct addrinfo hints;
  memset(&hints, 0, sizeof(hints));
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  struct addrinfo *results = NULL;
  int gai_error = getaddrinfo(resolver->name, NULL, &hints, &results);
  size_t count = 0;
  if (gai_error == 0) {
    for (struct addrinfo *current = results;
         current != NULL;
         current = current->ai_next) {
      if (current->ai_family == AF_INET) {
        count++;
      } else if (current->ai_family == AF_INET6) {
        struct sockaddr_in6 *address =
          (struct sockaddr_in6 *)current->ai_addr;
        if (!wasmoon_wasi_is_mapped_ipv4(&address->sin6_addr)) count++;
      }
    }
  }
  struct wasmoon_wasi_resolver_address *addresses = NULL;
  if (count > 0) {
    addresses = calloc(count, sizeof(*addresses));
    if (addresses == NULL) {
      gai_error = EAI_MEMORY;
      count = 0;
    }
  }
  size_t index = 0;
  if (gai_error == 0) {
    for (struct addrinfo *current = results;
         current != NULL && index < count;
         current = current->ai_next) {
      if (current->ai_family == AF_INET) {
        struct sockaddr_in *address = (struct sockaddr_in *)current->ai_addr;
        addresses[index].family = 4;
        memcpy(addresses[index].address, &address->sin_addr, 4);
        index++;
      } else if (current->ai_family == AF_INET6) {
        struct sockaddr_in6 *address =
          (struct sockaddr_in6 *)current->ai_addr;
        if (wasmoon_wasi_is_mapped_ipv4(&address->sin6_addr)) continue;
        addresses[index].family = 6;
        addresses[index].scope_id = address->sin6_scope_id;
        memcpy(addresses[index].address, &address->sin6_addr, 16);
        index++;
      }
    }
  }
  if (results != NULL) freeaddrinfo(results);

  wasmoon_wasi_resolver_lock(resolver);
  resolver->gai_error = gai_error;
  resolver->addresses = addresses;
  resolver->count = index;
  resolver->completed = 1;
  int dropped = resolver->dropped;
  int write_fd = resolver->write_fd;
  resolver->write_fd = -1;
  wasmoon_wasi_resolver_unlock(resolver);
  if (write_fd >= 0) {
    uint8_t ready = 1;
#ifdef _WIN32
    (void)wasmoon_windows_write(write_fd, &ready, sizeof(ready));
#else
    ssize_t written;
    do { written = write(write_fd, &ready, sizeof(ready)); }
    while (written < 0 && errno == EINTR);
#endif
    wasmoon_wasi_resolver_close(write_fd);
  }
  if (dropped) wasmoon_wasi_resolver_free(resolver);
  return 0;
}

MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_resolver_start(
  moonbit_bytes_t name,
  int *poll_fd
) {
  int pipe_fds[2];
#ifdef _WIN32
  if (wasmoon_windows_notification_pipe(pipe_fds) != 0) return 0;
#else
  if (pipe(pipe_fds) != 0) return 0;
  int flags = fcntl(pipe_fds[0], F_GETFL, 0);
  if (flags < 0 || fcntl(pipe_fds[0], F_SETFL, flags | O_NONBLOCK) != 0) {
    wasmoon_wasi_resolver_close(pipe_fds[0]);
    wasmoon_wasi_resolver_close(pipe_fds[1]);
    return 0;
  }
#endif
  struct wasmoon_wasi_resolver *resolver = calloc(1, sizeof(*resolver));
  if (resolver == NULL) {
    wasmoon_wasi_resolver_close(pipe_fds[0]);
    wasmoon_wasi_resolver_close(pipe_fds[1]);
    return 0;
  }
  resolver->read_fd = pipe_fds[0];
  resolver->write_fd = pipe_fds[1];
#ifdef _WIN32
  resolver->name = _strdup((const char *)name);
  InitializeSRWLock(&resolver->mutex);
  int mutex_error = 0;
#else
  resolver->name = strdup((const char *)name);
  int mutex_error = pthread_mutex_init(&resolver->mutex, NULL);
#endif
  if (resolver->name == NULL || mutex_error != 0) {
#ifndef _WIN32
    if (mutex_error == 0) pthread_mutex_destroy(&resolver->mutex);
#endif
    wasmoon_wasi_resolver_close(pipe_fds[0]);
    wasmoon_wasi_resolver_close(pipe_fds[1]);
    free(resolver->name);
    free(resolver);
    return 0;
  }
#ifdef _WIN32
  uintptr_t thread = _beginthreadex(NULL, 0, wasmoon_wasi_resolver_run, resolver, 0, NULL);
  if (!thread) {
    wasmoon_wasi_resolver_free(resolver);
    return 0;
  }
  CloseHandle((HANDLE)thread);
#else
  pthread_t thread;
  if (pthread_create(&thread, NULL, wasmoon_wasi_resolver_run, resolver) != 0) {
    wasmoon_wasi_resolver_free(resolver);
    return 0;
  }
  pthread_detach(thread);
#endif
  *poll_fd = resolver->read_fd;
  return (int64_t)(intptr_t)resolver;
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_resolver_next(
  int64_t resolver_handle,
  uint8_t *family,
  uint8_t *address,
  uint32_t *scope_id
) {
  struct wasmoon_wasi_resolver *resolver =
    (struct wasmoon_wasi_resolver *)(intptr_t)resolver_handle;
  wasmoon_wasi_resolver_lock(resolver);
  if (!resolver->completed) {
    wasmoon_wasi_resolver_unlock(resolver);
    return 1;
  }
  if (resolver->gai_error != 0) {
    int error = resolver->gai_error;
    wasmoon_wasi_resolver_unlock(resolver);
    if (error == EAI_AGAIN) return 4;
#if defined(EAI_NONAME)
    if (error == EAI_NONAME) return 3;
#endif
#if defined(EAI_NODATA) && EAI_NODATA != EAI_NONAME
    if (error == EAI_NODATA) return 3;
#endif
    return 5;
  }
  if (resolver->index >= resolver->count) {
    wasmoon_wasi_resolver_unlock(resolver);
    return 2;
  }
  struct wasmoon_wasi_resolver_address *result =
    &resolver->addresses[resolver->index++];
  *family = result->family;
  memset(address, 0, 16);
  memcpy(address, result->address, result->family == 4 ? 4 : 16);
  *scope_id = result->scope_id;
  wasmoon_wasi_resolver_unlock(resolver);
  return 0;
}

MOONBIT_FFI_EXPORT void wasmoon_wasi_resolver_drop(int64_t resolver_handle) {
  struct wasmoon_wasi_resolver *resolver =
    (struct wasmoon_wasi_resolver *)(intptr_t)resolver_handle;
  if (resolver == NULL) return;
  wasmoon_wasi_resolver_lock(resolver);
  resolver->dropped = 1;
  int completed = resolver->completed;
  int read_fd = resolver->read_fd;
  resolver->read_fd = -1;
  wasmoon_wasi_resolver_unlock(resolver);
  if (read_fd >= 0) wasmoon_wasi_resolver_close(read_fd);
  if (completed) wasmoon_wasi_resolver_free(resolver);
}
