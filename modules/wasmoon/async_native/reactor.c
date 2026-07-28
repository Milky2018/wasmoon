#define _GNU_SOURCE

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h>

#include "moonbit.h"

#if defined(__APPLE__)
#include <sys/event.h>
#include <sys/time.h>
#elif defined(__linux__)
#include <fcntl.h>
#include <sys/epoll.h>
#include <sys/eventfd.h>
#include <sys/timerfd.h>
#endif

#if defined(__linux__)
typedef struct wasmoon_async_registration {
  int64_t token;
  int descriptor;
  struct wasmoon_async_registration *next;
} wasmoon_async_registration_t;
#endif

typedef struct {
  int handle;
  int wake_handle;
  int last_errno;
#if defined(__linux__)
  wasmoon_async_registration_t *registrations;
#endif
} wasmoon_async_reactor_t;

#if defined(__linux__)
static int wasmoon_async_remove_registration(
  wasmoon_async_reactor_t *reactor,
  int64_t token
) {
  wasmoon_async_registration_t **link = &reactor->registrations;
  while (*link) {
    wasmoon_async_registration_t *registration = *link;
    if (registration->token == token) {
      int descriptor = registration->descriptor;
      *link = registration->next;
      free(registration);
      return descriptor;
    }
    link = &registration->next;
  }
  return -1;
}

static int wasmoon_async_install_registration(
  wasmoon_async_reactor_t *reactor,
  int descriptor,
  uint32_t events,
  int64_t token
) {
  wasmoon_async_registration_t *registration = malloc(sizeof(*registration));
  if (!registration) {
    close(descriptor);
    reactor->last_errno = ENOMEM;
    return ENOMEM;
  }
  struct epoll_event event = {
    .events = events | EPOLLONESHOT,
    .data.u64 = (uint64_t)token,
  };
  if (epoll_ctl(reactor->handle, EPOLL_CTL_ADD, descriptor, &event) != 0) {
    int error = errno;
    free(registration);
    close(descriptor);
    reactor->last_errno = error;
    return error;
  }
  registration->token = token;
  registration->descriptor = descriptor;
  registration->next = reactor->registrations;
  reactor->registrations = registration;
  return 0;
}
#endif

static void wasmoon_async_reactor_finalize(void *self) {
  wasmoon_async_reactor_t *reactor = self;
#if defined(__linux__)
  while (reactor->registrations) {
    wasmoon_async_registration_t *registration = reactor->registrations;
    reactor->registrations = registration->next;
    close(registration->descriptor);
    free(registration);
  }
#endif
  if (reactor->wake_handle >= 0) {
    close(reactor->wake_handle);
  }
  if (reactor->handle >= 0) {
    close(reactor->handle);
  }
  reactor->wake_handle = -1;
  reactor->handle = -1;
}

MOONBIT_FFI_EXPORT int wasmoon_async_reactor_supported(void) {
#if defined(__APPLE__) || defined(__linux__)
  return 1;
#else
  return 0;
#endif
}

MOONBIT_FFI_EXPORT void *wasmoon_async_reactor_alloc(void) {
  wasmoon_async_reactor_t *reactor =
    moonbit_make_external_object(
      wasmoon_async_reactor_finalize,
      sizeof(wasmoon_async_reactor_t)
    );
  if (!reactor) return NULL;
  reactor->handle = -1;
  reactor->wake_handle = -1;
  reactor->last_errno = 0;
#if defined(__linux__)
  reactor->registrations = NULL;
#endif
#if defined(__APPLE__)
  reactor->handle = kqueue();
  if (reactor->handle < 0) {
    reactor->last_errno = errno;
    return reactor;
  }
  struct kevent change;
  EV_SET(
    &change,
    1,
    EVFILT_USER,
    EV_ADD | EV_CLEAR,
    0,
    0,
    (void *)(intptr_t)0
  );
  if (kevent(reactor->handle, &change, 1, NULL, 0, NULL) != 0) {
    reactor->last_errno = errno;
    close(reactor->handle);
    reactor->handle = -1;
  }
#elif defined(__linux__)
  reactor->handle = epoll_create1(EPOLL_CLOEXEC);
  if (reactor->handle < 0) {
    reactor->last_errno = errno;
    return reactor;
  }
  reactor->wake_handle = eventfd(0, EFD_NONBLOCK | EFD_CLOEXEC);
  if (reactor->wake_handle < 0) {
    reactor->last_errno = errno;
    close(reactor->handle);
    reactor->handle = -1;
    return reactor;
  }
  struct epoll_event wake_event = {
    .events = EPOLLIN,
    .data.u64 = 0,
  };
  if (epoll_ctl(
        reactor->handle,
        EPOLL_CTL_ADD,
        reactor->wake_handle,
        &wake_event
      ) != 0) {
    reactor->last_errno = errno;
    close(reactor->wake_handle);
    close(reactor->handle);
    reactor->wake_handle = -1;
    reactor->handle = -1;
  }
#endif
  return reactor;
}

MOONBIT_FFI_EXPORT int wasmoon_async_reactor_state(void *managed) {
  wasmoon_async_reactor_t *reactor = managed;
  return reactor && reactor->handle >= 0 ? 0 : -1;
}

MOONBIT_FFI_EXPORT int wasmoon_async_reactor_errno(void *managed) {
  wasmoon_async_reactor_t *reactor = managed;
  return reactor ? reactor->last_errno : EINVAL;
}

MOONBIT_FFI_EXPORT int wasmoon_async_reactor_register_fd(
  void *managed,
  int fd,
  int writable,
  int64_t token
) {
  wasmoon_async_reactor_t *reactor = managed;
  if (!reactor || reactor->handle < 0 || fd < 0 || token <= 0) return EINVAL;
#if defined(__APPLE__)
  struct kevent change;
  EV_SET(
    &change,
    (uintptr_t)fd,
    writable ? EVFILT_WRITE : EVFILT_READ,
    EV_ADD | EV_ONESHOT,
    0,
    0,
    (void *)(intptr_t)token
  );
  if (kevent(reactor->handle, &change, 1, NULL, 0, NULL) != 0) {
    reactor->last_errno = errno;
    return errno;
  }
  return 0;
#elif defined(__linux__)
  int duplicate = fcntl(fd, F_DUPFD_CLOEXEC, 0);
  if (duplicate < 0) {
    reactor->last_errno = errno;
    return errno;
  }
  return wasmoon_async_install_registration(
    reactor,
    duplicate,
    writable ? EPOLLOUT : EPOLLIN,
    token
  );
#else
  (void)writable;
  return ENOTSUP;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_async_reactor_register_timer(
  void *managed,
  int64_t delay_ns,
  int64_t token
) {
  wasmoon_async_reactor_t *reactor = managed;
  if (!reactor || reactor->handle < 0 || delay_ns <= 0 || token <= 0) {
    return EINVAL;
  }
#if defined(__APPLE__)
  struct kevent change;
  EV_SET(
    &change,
    (uintptr_t)token,
    EVFILT_TIMER,
    EV_ADD | EV_ONESHOT,
    NOTE_NSECONDS,
    delay_ns,
    (void *)(intptr_t)token
  );
  if (kevent(reactor->handle, &change, 1, NULL, 0, NULL) != 0) {
    reactor->last_errno = errno;
    return errno;
  }
  return 0;
#elif defined(__linux__)
  int timer = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC);
  if (timer < 0) {
    reactor->last_errno = errno;
    return errno;
  }
  struct itimerspec interval = {
    .it_interval = { .tv_sec = 0, .tv_nsec = 0 },
    .it_value = {
      .tv_sec = delay_ns / 1000000000LL,
      .tv_nsec = delay_ns % 1000000000LL,
    },
  };
  if (timerfd_settime(timer, 0, &interval, NULL) != 0) {
    int error = errno;
    close(timer);
    reactor->last_errno = error;
    return error;
  }
  return wasmoon_async_install_registration(reactor, timer, EPOLLIN, token);
#else
  return ENOTSUP;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_async_reactor_cancel(
  void *managed,
  int64_t token,
  int64_t ident,
  int filter
) {
  wasmoon_async_reactor_t *reactor = managed;
  if (!reactor || reactor->handle < 0) return EINVAL;
#if defined(__APPLE__)
  (void)token;
  struct kevent change;
  EV_SET(
    &change,
    (uintptr_t)ident,
    (short)filter,
    EV_DELETE,
    0,
    0,
    NULL
  );
  if (kevent(reactor->handle, &change, 1, NULL, 0, NULL) != 0 &&
      errno != ENOENT) {
    reactor->last_errno = errno;
    return errno;
  }
  return 0;
#elif defined(__linux__)
  (void)ident;
  (void)filter;
  int descriptor = wasmoon_async_remove_registration(reactor, token);
  if (descriptor < 0) return 0;
  epoll_ctl(reactor->handle, EPOLL_CTL_DEL, descriptor, NULL);
  close(descriptor);
  return 0;
#else
  (void)token;
  (void)ident;
  (void)filter;
  return ENOTSUP;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_async_reactor_wait(
  void *managed,
  int64_t timeout_ns,
  int64_t *tokens,
  int capacity
) {
  wasmoon_async_reactor_t *reactor = managed;
  if (!reactor || reactor->handle < 0 || !tokens || capacity <= 0) {
    if (reactor) reactor->last_errno = EINVAL;
    return -1;
  }
#if defined(__APPLE__)
  struct timespec timeout;
  struct timespec *timeout_ptr = NULL;
  if (timeout_ns >= 0) {
    timeout.tv_sec = timeout_ns / 1000000000LL;
    timeout.tv_nsec = timeout_ns % 1000000000LL;
    timeout_ptr = &timeout;
  }
  struct kevent *events = calloc((size_t)capacity, sizeof(struct kevent));
  if (!events) {
    reactor->last_errno = ENOMEM;
    return -1;
  }
  int count = kevent(
    reactor->handle,
    NULL,
    0,
    events,
    capacity,
    timeout_ptr
  );
  if (count < 0) {
    reactor->last_errno = errno;
    free(events);
    return -1;
  }
  for (int i = 0; i < count; i++) {
    tokens[i] = (int64_t)(intptr_t)events[i].udata;
  }
  free(events);
  return count;
#elif defined(__linux__)
  struct epoll_event *events = calloc((size_t)capacity, sizeof(*events));
  if (!events) {
    reactor->last_errno = ENOMEM;
    return -1;
  }
  int timeout_ms = -1;
  if (timeout_ns >= 0) {
    int64_t rounded_ms = timeout_ns / 1000000LL;
    if (timeout_ns % 1000000LL != 0) rounded_ms++;
    timeout_ms = rounded_ms > INT_MAX ? INT_MAX : (int)rounded_ms;
  }
  int count = epoll_wait(reactor->handle, events, capacity, timeout_ms);
  if (count < 0) {
    reactor->last_errno = errno;
    free(events);
    return -1;
  }
  for (int i = 0; i < count; i++) {
    int64_t token = (int64_t)events[i].data.u64;
    tokens[i] = token;
    if (token == 0) {
      uint64_t pending;
      while (read(reactor->wake_handle, &pending, sizeof(pending)) > 0) {
      }
      continue;
    }
    int descriptor = wasmoon_async_remove_registration(reactor, token);
    if (descriptor >= 0) {
      epoll_ctl(reactor->handle, EPOLL_CTL_DEL, descriptor, NULL);
      close(descriptor);
    }
  }
  free(events);
  return count;
#else
  (void)timeout_ns;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_async_reactor_wake(void *managed) {
  wasmoon_async_reactor_t *reactor = managed;
  if (!reactor || reactor->handle < 0) return EINVAL;
#if defined(__APPLE__)
  struct kevent change;
  EV_SET(
    &change,
    1,
    EVFILT_USER,
    0,
    NOTE_TRIGGER,
    0,
    (void *)(intptr_t)0
  );
  if (kevent(reactor->handle, &change, 1, NULL, 0, NULL) != 0) {
    reactor->last_errno = errno;
    return errno;
  }
  return 0;
#elif defined(__linux__)
  uint64_t value = 1;
  if (write(reactor->wake_handle, &value, sizeof(value)) < 0 &&
      errno != EAGAIN) {
    reactor->last_errno = errno;
    return errno;
  }
  return 0;
#else
  return ENOTSUP;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_async_test_pipe(int *fds) {
#if defined(__APPLE__) || defined(__linux__)
  return fds ? pipe(fds) : -1;
#else
  (void)fds;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_async_test_write(int fd) {
#if defined(__APPLE__) || defined(__linux__)
  uint8_t byte = 1;
  return (int)write(fd, &byte, sizeof(byte));
#else
  (void)fd;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT void wasmoon_async_test_close(int fd) {
#if defined(__APPLE__) || defined(__linux__)
  if (fd >= 0) close(fd);
#else
  (void)fd;
#endif
}
