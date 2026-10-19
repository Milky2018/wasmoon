#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
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
#ifdef __APPLE__
#include <sys/event.h>
#endif
#endif

struct wasmoon_wasi_resolver_address {
  uint8_t family;
  uint8_t address[16];
  uint32_t scope_id;
};

struct wasmoon_wasi_resolver {
  struct wasmoon_wasi_resolver *next;
  int queued;
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

// Global admission accounts for queued and executing work, including cancelled
// getaddrinfo calls until they return. Idle workers exit; no shutdown join can
// be held hostage by the system resolver. All queue and result state uses this
// mutex, but no name lookup runs while it is held.
enum { RESOLVER_WORKERS = 4, RESOLVER_REQUESTS = 32 };
static struct wasmoon_wasi_resolver *resolver_queue;
static struct wasmoon_wasi_resolver *resolver_tail;
static int resolver_workers;
static int resolver_requests;
#ifdef _WIN32
static SRWLOCK resolver_mutex = SRWLOCK_INIT;
#else
static pthread_mutex_t resolver_mutex = PTHREAD_MUTEX_INITIALIZER;
#endif
static void resolver_lock(void) {
#ifdef _WIN32
  AcquireSRWLockExclusive(&resolver_mutex);
#else
  pthread_mutex_lock(&resolver_mutex);
#endif
}
static void resolver_unlock(void) {
#ifdef _WIN32
  ReleaseSRWLockExclusive(&resolver_mutex);
#else
  pthread_mutex_unlock(&resolver_mutex);
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
  free(resolver);
}

static int wasmoon_wasi_is_mapped_ipv4(const struct in6_addr *address) {
  const uint8_t *bytes = (const uint8_t *)address;
  for (int i = 0; i < 10; i++) {
    if (bytes[i] != 0) return 0;
  }
  return bytes[10] == 0xff && bytes[11] == 0xff;
}

static void resolver_lookup(struct wasmoon_wasi_resolver *resolver) {
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

  resolver_lock();
  resolver->gai_error = gai_error;
  resolver->addresses = addresses;
  resolver->count = index;
  resolver->completed = 1;
  resolver_requests--;
  int dropped = resolver->dropped;
  int write_fd = resolver->write_fd;
  resolver->write_fd = -1;
  // Keep notification and closing the read end mutually exclusive.
#ifdef __APPLE__
  if (!dropped) {
    struct kevent event;
    EV_SET(&event, 1, EVFILT_USER, 0, NOTE_TRIGGER, 0, NULL);
    int result;
    do { result = kevent(resolver->read_fd, &event, 1, NULL, 0, NULL); }
    while (result < 0 && errno == EINTR);
  }
#else
  if (write_fd >= 0 && !dropped) {
    uint8_t ready = 1;
#ifdef _WIN32
    (void)wasmoon_windows_write(write_fd, &ready, sizeof(ready));
#else
    ssize_t written;
    do { written = write(write_fd, &ready, sizeof(ready)); }
    while (written < 0 && errno == EINTR);
#endif
  }
#endif
  if (write_fd >= 0) wasmoon_wasi_resolver_close(write_fd);
  resolver_unlock();
  if (dropped) wasmoon_wasi_resolver_free(resolver);
}

#ifdef _WIN32
static unsigned __stdcall resolver_worker(void *argument) {
#else
static void *resolver_worker(void *argument) {
#endif
  (void)argument;
  for (;;) {
    resolver_lock();
    struct wasmoon_wasi_resolver *resolver = resolver_queue;
    if (resolver == NULL) {
      resolver_workers--;
      resolver_unlock();
      return 0;
    }
    resolver_queue = resolver->next;
    if (resolver_queue == NULL) resolver_tail = NULL;
    resolver->next = NULL;
    resolver->queued = 0;
    resolver_unlock();
    resolver_lookup(resolver);
  }
}

// Must be called with resolver_mutex held, before publishing a new request.
static int resolver_start_worker(void) {
#ifdef _WIN32
  uintptr_t thread = _beginthreadex(NULL, 0, resolver_worker, NULL, 0, NULL);
  if (!thread) return -1;
  CloseHandle((HANDLE)thread);
#else
  pthread_attr_t attr;
  int error = pthread_attr_init(&attr);
  if (error) { errno = error; return -1; }
  error = pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
  pthread_t thread;
  if (!error) error = pthread_create(&thread, &attr, resolver_worker, NULL);
  pthread_attr_destroy(&attr);
  if (error) { errno = error; return -1; }
#endif
  resolver_workers++;
  return 0;
}

static int resolver_notification(int *fds) {
#ifdef _WIN32
  return wasmoon_windows_notification_pipe(fds);
#elif defined(__APPLE__)
  // Darwin kqueues are close-on-exec and close-on-fork at creation. Poll and
  // nested kqueue registration observe pending EVFILT_USER events as readable.
  fds[0] = kqueue();
  fds[1] = -1;
  if (fds[0] < 0) return -1;
  struct kevent event;
  EV_SET(&event, 1, EVFILT_USER, EV_ADD | EV_CLEAR, 0, 0, NULL);
  if (kevent(fds[0], &event, 1, NULL, 0, NULL) == 0) return 0;
  int error = errno;
  close(fds[0]);
  errno = error;
  return -1;
#else
  return pipe2(fds, O_CLOEXEC | O_NONBLOCK);
#endif
}

static struct wasmoon_wasi_resolver *resolver_start(
  moonbit_bytes_t name,
  int *poll_fd
) {
  int pipe_fds[2];
  if (resolver_notification(pipe_fds) != 0) return NULL;
  struct wasmoon_wasi_resolver *resolver = calloc(1, sizeof(*resolver));
  if (resolver == NULL) {
    wasmoon_wasi_resolver_close(pipe_fds[0]);
    if (pipe_fds[1] >= 0) wasmoon_wasi_resolver_close(pipe_fds[1]);
    return 0;
  }
  resolver->read_fd = pipe_fds[0];
  resolver->write_fd = pipe_fds[1];
#ifdef _WIN32
  resolver->name = _strdup((const char *)name);
#else
  resolver->name = strdup((const char *)name);
#endif
  if (resolver->name == NULL) {
    wasmoon_wasi_resolver_free(resolver);
    return NULL;
  }
  resolver_lock();
  if (resolver_requests == RESOLVER_REQUESTS ||
      (resolver_workers < RESOLVER_WORKERS &&
       resolver_start_worker() != 0 && resolver_workers == 0)) {
    resolver_unlock();
    wasmoon_wasi_resolver_free(resolver);
    errno = EAGAIN;
    return NULL;
  }
  resolver_requests++;
  resolver->queued = 1;
  if (resolver_tail) resolver_tail->next = resolver;
  else resolver_queue = resolver;
  resolver_tail = resolver;
  resolver_unlock();
  *poll_fd = resolver->read_fd;
  return resolver;
}

// The MoonBit-owned shell survives explicit close. Only the worker state is
// shared with the background thread; its last owner frees it under the protocol
// below. The worker never accesses a MoonBit object or its reference count.
struct wasmoon_wasi_resolver_handle {
  struct wasmoon_wasi_resolver *state;
};

MOONBIT_FFI_EXPORT void wasmoon_wasi_resolver_drop(
  struct wasmoon_wasi_resolver_handle *handle
) {
  struct wasmoon_wasi_resolver *resolver = handle->state;
  if (resolver == NULL) return;
  handle->state = NULL;
  resolver_lock();
  resolver->dropped = 1;
  int completed = resolver->completed;
  if (resolver->queued) {
    struct wasmoon_wasi_resolver *previous = NULL;
    struct wasmoon_wasi_resolver **link = &resolver_queue;
    while (*link != resolver) {
      previous = *link;
      link = &(*link)->next;
    }
    *link = resolver->next;
    if (resolver_tail == resolver) resolver_tail = previous;
    resolver_requests--;
    completed = 1;
  }
  if (resolver->read_fd >= 0) {
    wasmoon_wasi_resolver_close(resolver->read_fd);
    resolver->read_fd = -1;
  }
  resolver_unlock();
  if (completed) wasmoon_wasi_resolver_free(resolver);
}

static void resolver_finalize(void *object) {
  wasmoon_wasi_resolver_drop(object);
}

MOONBIT_FFI_EXPORT struct wasmoon_wasi_resolver_handle *wasmoon_wasi_resolver_start(
  moonbit_bytes_t name, int *poll_fd
) {
  struct wasmoon_wasi_resolver_handle *handle = moonbit_make_external_object(
    resolver_finalize, sizeof(*handle));
  *poll_fd = -1;
  handle->state = resolver_start(name, poll_fd);
  return handle;
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_resolver_next(
  struct wasmoon_wasi_resolver_handle *handle,
  uint8_t *family,
  uint8_t *address,
  uint32_t *scope_id
) {
  struct wasmoon_wasi_resolver *resolver = handle->state;
  if (resolver == NULL) return 5;
  resolver_lock();
  if (!resolver->completed) {
    resolver_unlock();
    return 1;
  }
  if (resolver->gai_error != 0) {
    int error = resolver->gai_error;
    resolver_unlock();
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
    resolver_unlock();
    return 2;
  }
  struct wasmoon_wasi_resolver_address *result =
    &resolver->addresses[resolver->index++];
  *family = result->family;
  memset(address, 0, 16);
  memcpy(address, result->address, result->family == 4 ? 4 : 16);
  *scope_id = result->scope_id;
  resolver_unlock();
  return 0;
}
