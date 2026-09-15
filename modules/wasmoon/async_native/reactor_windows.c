#ifdef _WIN32
#include "../../wasmoon_jit/host_io/windows_input.h"
#include <limits.h>
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
  wasmoon_notification wake;
  int open;
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
  if (reactor->open) wasmoon_notification_close(&reactor->wake);
  reactor->open = 0;
}
MOONBIT_FFI_EXPORT int wasmoon_async_reactor_supported(void) { return 1; }
MOONBIT_FFI_EXPORT void *wasmoon_async_reactor_alloc(void) {
  windows_reactor *reactor = moonbit_make_external_object(finalize_reactor, sizeof(*reactor));
  if (!reactor) return NULL;
  reactor->registrations = NULL;
  reactor->open = wasmoon_notification_init(&reactor->wake) == 0;
  reactor->last_errno = reactor->open ? 0 : errno;
  return reactor;
}
MOONBIT_FFI_EXPORT void wasmoon_async_reactor_close(void *object) {
  if (object) finalize_reactor(object);
}
MOONBIT_FFI_EXPORT int wasmoon_async_reactor_state(void *object) {
  windows_reactor *reactor = object;
  return reactor && reactor->open ? 0 : -1;
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
  if (!reactor || !reactor->open || fd < 0 || token <= 0) return EINVAL;
  int duplicate = wasmoon_windows_dup(fd);
  if (duplicate < 0) return reactor->last_errno = errno;
  return register_event(reactor, duplicate, writable ? 4 : 1, 0, token);
}
MOONBIT_FFI_EXPORT int wasmoon_async_reactor_register_timer(void *object,
                                                           int64_t delay, int64_t token) {
  windows_reactor *reactor = object;
  if (!reactor || !reactor->open || delay <= 0 || token <= 0) return EINVAL;
  return register_event(reactor, -1, 0, after_ns(now_ns(), delay), token);
}
MOONBIT_FFI_EXPORT int wasmoon_async_reactor_cancel(void *object, int64_t token) {
  windows_reactor *reactor = object;
  if (!reactor || !reactor->open || token <= 0) return EINVAL;
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
  if (!reactor || !reactor->open || !tokens || capacity <= 0) {
    if (reactor) reactor->last_errno = EINVAL;
    return -1;
  }
  uint64_t deadline = timeout < 0 ? UINT64_MAX : after_ns(now_ns(), timeout);
  for (;;) {
    int count = 0;
    WSAPOLLFD wake = {reactor->wake.reader, POLLRDNORM, 0};
    if (WSAPoll(&wake, 1, 0) > 0) {
      wasmoon_notification_clear(&reactor->wake);
      tokens[count++] = 0;
    }
    uint64_t now = now_ns(), next = deadline;
    int descriptor_count = 0;
    registration **link = &reactor->registrations;
    while (*link && count < capacity) {
      registration *item = *link;
      int ready;
      if (item->descriptor < 0) {
        ready = now >= item->deadline;
        if (item->deadline < next) next = item->deadline;
      } else {
        descriptor_count++;
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
    int wait = next == UINT64_MAX ? -1 : ms > INT_MAX ? INT_MAX : (int)ms;
    int *fds = malloc(((size_t)descriptor_count + 1) * 3 * sizeof(int));
    if (!fds) { reactor->last_errno = ENOMEM; return -1; }
    int *events = fds + descriptor_count, *revents = events + descriptor_count;
    int index = 0;
    for (registration *item = reactor->registrations; item; item = item->next) {
      if (item->descriptor >= 0) {
        fds[index] = item->descriptor;
        events[index++] = item->events;
      }
    }
    int woken;
    int result = wasmoon_windows_poll_interruptible(fds, events, revents,
        descriptor_count, wait, reactor->wake.reader, &woken);
    free(fds);
    if (result < 0) { reactor->last_errno = errno; return -1; }
    if (woken) {
      wasmoon_notification_clear(&reactor->wake);
      tokens[0] = 0;
      return 1;
    }
  }
}
MOONBIT_FFI_EXPORT int wasmoon_async_reactor_wake(void *object) {
  windows_reactor *reactor = object;
  if (!reactor || !reactor->open) return EINVAL;
  wasmoon_notification_signal(&reactor->wake);
  return 0;
}
MOONBIT_FFI_EXPORT int wasmoon_async_test_pipe(int *fds) {
  // Other test packages also redirect these descriptors onto CRT stdin.
  return _pipe(fds, 4096, _O_BINARY | _O_NOINHERIT);
}
MOONBIT_FFI_EXPORT int wasmoon_async_test_write(int fd) {
  return wasmoon_windows_write(fd, "x", 1);
}
MOONBIT_FFI_EXPORT void wasmoon_async_test_close(int fd) { wasmoon_windows_close(fd); }
#endif
