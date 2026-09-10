// Copyright 2026
// Native readiness backend shared by interpreter and JIT WASI polling.
#if defined(__APPLE__)
// Darwin permits dynamically sized fd_sets when this is defined before headers.
#define _DARWIN_UNLIMITED_SELECT
#endif
#include <errno.h>
#include <stdlib.h>
#include "moonbit.h"
#ifndef _WIN32
#include <poll.h>
#if defined(__APPLE__)
#include <fcntl.h>
#include <sys/select.h>

// Darwin poll reports POLLNVAL for some valid devices, including /dev/null.
// Use select only when that limitation is encountered. Poll remains responsible
// for normal error/hangup flags; select supplies readiness for unsupported fds.
static int poll_darwin_devices(struct pollfd *pfds, int nfds, int timeout_ms) {
  int fallback = 0;
  int immediate = 0;
  int max_fd = -1;
  for (int i = 0; i < nfds; i++) {
    if (pfds[i].fd < 0) continue;
    if ((pfds[i].revents & POLLNVAL) && fcntl(pfds[i].fd, F_GETFD) >= 0) {
      fallback = 1;
      pfds[i].revents = 0;
    }
    if (pfds[i].revents) immediate = 1;
    if (!(pfds[i].revents & POLLNVAL) && pfds[i].fd > max_fd)
      max_fd = pfds[i].fd;
  }
  if (!fallback) return -2;

  size_t bytes = ((size_t)max_fd / 32 + 1) * sizeof(int32_t);
  if (bytes < sizeof(fd_set)) bytes = sizeof(fd_set);
  fd_set *readers = calloc(1, bytes);
  fd_set *writers = calloc(1, bytes);
  if (!readers || !writers) {
    free(readers);
    free(writers);
    errno = ENOMEM;
    return -1;
  }
  for (int i = 0; i < nfds; i++) {
    if (pfds[i].fd < 0 || (pfds[i].revents & POLLNVAL)) continue;
    if (pfds[i].events & POLLIN) FD_SET(pfds[i].fd, readers);
    if (pfds[i].events & POLLOUT) FD_SET(pfds[i].fd, writers);
  }
  int wait_ms = immediate ? 0 : timeout_ms;
  struct timeval timeout = { wait_ms / 1000, (wait_ms % 1000) * 1000 };
  int result = select(max_fd + 1, readers, writers, NULL,
                      wait_ms < 0 ? NULL : &timeout);
  int saved_errno = errno;
  if (result >= 0) {
    // Refresh native flags after the wait, then replace only false POLLNVAL.
    result = poll(pfds, nfds, 0);
    saved_errno = errno;
    if (result >= 0) {
      result = 0;
      for (int i = 0; i < nfds; i++) {
        int fd = pfds[i].fd;
        if (fd >= 0 && fd <= max_fd && (pfds[i].revents & POLLNVAL)
            && fcntl(fd, F_GETFD) >= 0) {
          pfds[i].revents = 0;
          if ((pfds[i].events & POLLIN) && FD_ISSET(fd, readers))
            pfds[i].revents |= POLLIN;
          if ((pfds[i].events & POLLOUT) && FD_ISSET(fd, writers))
            pfds[i].revents |= POLLOUT;
        }
        if (pfds[i].revents) result++;
      }
    }
  }
  free(readers);
  free(writers);
  errno = saved_errno;
  return result;
}
#endif
#endif

// Parallel fd/event arrays; timeout_ms is -1 for an unbounded wait.
MOONBIT_FFI_EXPORT int wasmoon_wasi_poll(int *fds_ptr, int *events_ptr,
    int *revents_ptr, int nfds, int timeout_ms) {
#ifdef _WIN32
  (void)fds_ptr;
  (void)events_ptr;
  (void)revents_ptr;
  (void)nfds;
  (void)timeout_ms;
  errno = ENOSYS;
  return -1;
#else
  if (nfds <= 0) {
    errno = EINVAL;
    return -1;
  }
  struct pollfd *pfds = calloc((size_t)nfds, sizeof(struct pollfd));
  if (!pfds) return -1;
  for (int i = 0; i < nfds; i++) {
    pfds[i].fd = fds_ptr[i];
    pfds[i].events = (short)events_ptr[i];
  }
  int result = poll(pfds, nfds, timeout_ms);
#if defined(__APPLE__)
  if (result > 0) {
    int fallback = poll_darwin_devices(pfds, nfds, timeout_ms);
    if (fallback != -2) result = fallback;
  }
#endif
  int saved_errno = errno;
  for (int i = 0; i < nfds; i++) revents_ptr[i] = pfds[i].revents;
  free(pfds);
  errno = saved_errno;
  return result;
#endif
}
