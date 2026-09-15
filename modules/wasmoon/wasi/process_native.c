#include <stdint.h>
#include <errno.h>
#include <signal.h>
#include "moonbit.h"
#ifdef _WIN32
#include "../../wasmoon_jit/host_io/windows_io.h"
#else
#include <time.h>
#include <unistd.h>
#include <sched.h>
#endif

MOONBIT_FFI_EXPORT int64_t wasmoon_wasi_cpu_clock(int thread, int resolution) {
#ifdef _WIN32
  if (resolution) {
    DWORD adjustment, increment; BOOL disabled;
    if (!GetSystemTimeAdjustment(&adjustment, &increment, &disabled)) {
      wasmoon_windows_error(GetLastError()); return -1;
    }
    return (int64_t)increment * 100;
  }
  FILETIME created, exited, kernel, user;
  BOOL ok = thread ? GetThreadTimes(GetCurrentThread(), &created, &exited, &kernel, &user)
                   : GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user);
  if (!ok) { wasmoon_windows_error(GetLastError()); return -1; }
  uint64_t ticks = (((uint64_t)kernel.dwHighDateTime << 32) | kernel.dwLowDateTime)
                 + (((uint64_t)user.dwHighDateTime << 32) | user.dwLowDateTime);
  return (int64_t)(ticks * 100);
#else
  struct timespec value;
  clockid_t id = thread ? CLOCK_THREAD_CPUTIME_ID : CLOCK_PROCESS_CPUTIME_ID;
  int result = resolution ? clock_getres(id, &value) : clock_gettime(id, &value);
  return result ? -1 : (int64_t)value.tv_sec * 1000000000 + value.tv_nsec;
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_yield(void) {
#ifdef _WIN32
  // FALSE means there was no runnable thread, not an error.
  SwitchToThread(); return 0;
#else
  return sched_yield();
#endif
}

MOONBIT_FFI_EXPORT int wasmoon_wasi_raise_signal(int signal) {
  int native;
  switch (signal) {
    case 0: return 0;
    case 2: native = SIGINT; break;
    case 4: native = SIGILL; break;
    case 6: native = SIGABRT; break;
    case 8: native = SIGFPE; break;
    case 11: native = SIGSEGV; break;
    case 15: native = SIGTERM; break;
#ifndef _WIN32
    case 1: native = SIGHUP; break;
    case 3: native = SIGQUIT; break;
    case 5: native = SIGTRAP; break;
    case 7: native = SIGBUS; break;
    case 9: native = SIGKILL; break;
    case 10: native = SIGUSR1; break;
    case 12: native = SIGUSR2; break;
    case 13: native = SIGPIPE; break;
    case 14: native = SIGALRM; break;
    case 16: native = SIGCHLD; break;
    case 17: native = SIGCONT; break;
    case 18: native = SIGSTOP; break;
    case 19: native = SIGTSTP; break;
    case 20: native = SIGTTIN; break;
    case 21: native = SIGTTOU; break;
    case 22: native = SIGURG; break;
    case 23: native = SIGXCPU; break;
    case 24: native = SIGXFSZ; break;
    case 25: native = SIGVTALRM; break;
    case 26: native = SIGPROF; break;
    case 27: native = SIGWINCH; break;
#ifdef SIGPOLL
    case 28: native = SIGPOLL; break;
#elif defined(SIGIO)
    case 28: native = SIGIO; break;
#endif
#ifdef SIGPWR
    case 29: native = SIGPWR; break;
#endif
    case 30: native = SIGSYS; break;
#endif
    default: errno = signal >= 0 && signal <= 30 ? ENOTSUP : EINVAL; return -1;
  }
#ifdef _WIN32
  return raise(native);
#else
  return kill(getpid(), native);
#endif
}
