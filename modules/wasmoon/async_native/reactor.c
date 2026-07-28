#include <errno.h>
#include <stdint.h>
#include <stdlib.h>

#include "moonbit.h"

#if defined(__APPLE__)
#include <sys/event.h>
#include <sys/time.h>
#include <unistd.h>
#endif

typedef struct {
  int handle;
  int last_errno;
} wasmoon_async_reactor_t;

static void wasmoon_async_reactor_finalize(void *self) {
  wasmoon_async_reactor_t *reactor = self;
#if defined(__APPLE__)
  if (reactor->handle >= 0) {
    close(reactor->handle);
  }
#endif
  reactor->handle = -1;
}

MOONBIT_FFI_EXPORT int wasmoon_async_reactor_supported(void) {
#if defined(__APPLE__)
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
  reactor->last_errno = 0;
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
#if defined(__APPLE__)
  wasmoon_async_reactor_t *reactor = managed;
  if (!reactor || reactor->handle < 0 || fd < 0 || token <= 0) return EINVAL;
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
#else
  (void)managed;
  (void)fd;
  (void)writable;
  (void)token;
  return ENOTSUP;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_async_reactor_register_timer(
  void *managed,
  int64_t delay_ns,
  int64_t token
) {
#if defined(__APPLE__)
  wasmoon_async_reactor_t *reactor = managed;
  if (!reactor || reactor->handle < 0 || delay_ns <= 0 || token <= 0) {
    return EINVAL;
  }
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
#else
  (void)managed;
  (void)delay_ns;
  (void)token;
  return ENOTSUP;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_async_reactor_cancel(
  void *managed,
  int64_t ident,
  int filter
) {
#if defined(__APPLE__)
  wasmoon_async_reactor_t *reactor = managed;
  if (!reactor || reactor->handle < 0) return EINVAL;
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
#else
  (void)managed;
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
#if defined(__APPLE__)
  wasmoon_async_reactor_t *reactor = managed;
  if (!reactor || reactor->handle < 0 || !tokens || capacity <= 0) return -1;
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
#else
  (void)managed;
  (void)timeout_ns;
  (void)tokens;
  (void)capacity;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_async_reactor_wake(void *managed) {
#if defined(__APPLE__)
  wasmoon_async_reactor_t *reactor = managed;
  if (!reactor || reactor->handle < 0) return EINVAL;
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
#else
  (void)managed;
  return ENOTSUP;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_async_test_pipe(int *fds) {
#if defined(__APPLE__)
  return fds ? pipe(fds) : -1;
#else
  (void)fds;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_async_test_write(int fd) {
#if defined(__APPLE__)
  uint8_t byte = 1;
  return (int)write(fd, &byte, sizeof(byte));
#else
  (void)fd;
  return -1;
#endif
}

MOONBIT_FFI_EXPORT void wasmoon_async_test_close(int fd) {
#if defined(__APPLE__)
  if (fd >= 0) close(fd);
#else
  (void)fd;
#endif
}
