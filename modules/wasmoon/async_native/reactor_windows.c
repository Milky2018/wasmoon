#ifdef _WIN32
#include "../../wasmoon_jit/host_io/windows_io.h"
#include "moonbit.h"
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct registration {
  int64_t token;
  int descriptor;
  int events;
  uint64_t deadline;
  struct registration *next;
} registration;

typedef struct {
  HANDLE wake;
  int last_errno;
  registration *registrations;
} windows_reactor;

static uint64_t now_ns(void) {
  LARGE_INTEGER counter, frequency;
  if (!QueryPerformanceCounter(&counter) || !QueryPerformanceFrequency(&frequency)) abort();
  uint64_t ticks = counter.QuadPart, hz = frequency.QuadPart;
  return ticks / hz * 1000000000ULL + ticks % hz * 1000000000ULL / hz;
}
static uint64_t after_ns(uint64_t now, uint64_t delay) {
  return delay > UINT64_MAX - now ? UINT64_MAX : now + delay;
}
static void release_registration(registration *item) {
  if (item->descriptor >= 0) wasmoon_windows_close(item->descriptor);
  free(item);
}
static void finalize_reactor(void *object) {
  windows_reactor *reactor = object;
  while (reactor->registrations) {
    registration *item = reactor->registrations;
    reactor->registrations = item->next;
    release_registration(item);
  }
  if (reactor->wake) CloseHandle(reactor->wake);
  reactor->wake = NULL;
}
MOONBIT_FFI_EXPORT int wasmoon_async_reactor_supported(void) { return 1; }
MOONBIT_FFI_EXPORT void *wasmoon_async_reactor_alloc(void) {
  windows_reactor *reactor = moonbit_make_external_object(finalize_reactor, sizeof(*reactor));
  if (!reactor) return NULL;
  reactor->registrations = NULL;
  reactor->wake = CreateEventW(NULL, FALSE, FALSE, NULL);
  reactor->last_errno = reactor->wake ? 0 : ENOMEM;
  return reactor;
}
MOONBIT_FFI_EXPORT void wasmoon_async_reactor_close(void *object) {
  if (object) finalize_reactor(object);
}
MOONBIT_FFI_EXPORT int wasmoon_async_reactor_state(void *object) {
  windows_reactor *reactor = object;
  return reactor && reactor->wake ? 0 : -1;
}
MOONBIT_FFI_EXPORT int wasmoon_async_reactor_errno(void *object) {
  windows_reactor *reactor = object;
  return reactor ? reactor->last_errno : EINVAL;
}
static int register_event(windows_reactor *reactor, int descriptor, int events,
                          uint64_t deadline, int64_t token) {
  registration *item = malloc(sizeof(*item));
  if (!item) {
    if (descriptor >= 0) wasmoon_windows_close(descriptor);
    return reactor->last_errno = ENOMEM;
  }
  *item = (registration){token, descriptor, events, deadline, reactor->registrations};
  reactor->registrations = item;
  return 0;
}
MOONBIT_FFI_EXPORT int wasmoon_async_reactor_register_fd(void *object, int fd,
                                                         int writable, int64_t token) {
  windows_reactor *reactor = object;
  if (!reactor || !reactor->wake || fd < 0 || token <= 0) return EINVAL;
  int duplicate = wasmoon_windows_dup(fd);
  if (duplicate < 0) return reactor->last_errno = errno;
  return register_event(reactor, duplicate, writable ? 4 : 1, 0, token);
}
MOONBIT_FFI_EXPORT int wasmoon_async_reactor_register_timer(void *object,
                                                           int64_t delay, int64_t token) {
  windows_reactor *reactor = object;
  if (!reactor || !reactor->wake || delay <= 0 || token <= 0) return EINVAL;
  return register_event(reactor, -1, 0, after_ns(now_ns(), delay), token);
}
MOONBIT_FFI_EXPORT int wasmoon_async_reactor_cancel(void *object, int64_t token) {
  windows_reactor *reactor = object;
  if (!reactor || !reactor->wake || token <= 0) return EINVAL;
  registration **link = &reactor->registrations;
  while (*link) {
    registration *item = *link;
    if (item->token == token) {
      *link = item->next;
      release_registration(item);
      break;
    }
    link = &item->next;
  }
  return 0;
}
MOONBIT_FFI_EXPORT int wasmoon_async_reactor_wait(void *object, int64_t timeout,
                                                 int64_t *tokens, int capacity) {
  windows_reactor *reactor = object;
  if (!reactor || !reactor->wake || !tokens || capacity <= 0) {
    if (reactor) reactor->last_errno = EINVAL;
    return -1;
  }
  uint64_t deadline = timeout < 0 ? UINT64_MAX : after_ns(now_ns(), timeout);
  for (;;) {
    int count = 0;
    if (WaitForSingleObject(reactor->wake, 0) == WAIT_OBJECT_0) tokens[count++] = 0;
    uint64_t now = now_ns(), next = deadline;
    int have_descriptors = 0;
    registration **link = &reactor->registrations;
    while (*link && count < capacity) {
      registration *item = *link;
      int ready;
      if (item->descriptor < 0) {
        ready = now >= item->deadline;
        if (item->deadline < next) next = item->deadline;
      } else {
        have_descriptors = 1;
        int flags;
        ready = wasmoon_windows_poll(&item->descriptor, &item->events, &flags, 1, 0);
        if (ready < 0) { reactor->last_errno = errno; return -1; }
      }
      if (ready) {
        tokens[count++] = item->token;
        *link = item->next;
        release_registration(item);
      } else link = &item->next;
    }
    if (count || now >= deadline) return count;
    uint64_t remaining = next > now ? next - now : 0;
    uint64_t ms = remaining / 1000000ULL + (remaining % 1000000ULL != 0);
    if (have_descriptors && ms > 10) ms = 10;
    DWORD wait = ms >= INFINITE ? INFINITE - 1 : (DWORD)ms;
    DWORD result = WaitForSingleObjectEx(reactor->wake, wait, TRUE);
    if (result == WAIT_OBJECT_0) { tokens[0] = 0; return 1; }
    if (result == WAIT_IO_COMPLETION) { reactor->last_errno = EINTR; return -1; }
    if (result == WAIT_FAILED) { reactor->last_errno = EIO; return -1; }
  }
}
MOONBIT_FFI_EXPORT int wasmoon_async_reactor_wake(void *object) {
  windows_reactor *reactor = object;
  if (!reactor || !reactor->wake) return EINVAL;
  return SetEvent(reactor->wake) ? 0 : (reactor->last_errno = EIO);
}
MOONBIT_FFI_EXPORT int wasmoon_async_test_pipe(int *fds) {
  return _pipe(fds, 4096, _O_BINARY | _O_NOINHERIT);
}
MOONBIT_FFI_EXPORT int wasmoon_async_test_write(int fd) {
  return _write(fd, "x", 1);
}
MOONBIT_FFI_EXPORT void wasmoon_async_test_close(int fd) { _close(fd); }
#endif
