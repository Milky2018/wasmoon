// Native Windows host context recovery must not ask the OS unwinder to walk
// generated guest frames. The runtime explicitly unwinds its owned resources.
#ifndef WASMOON_WINDOWS_CONTEXT_H
#define WASMOON_WINDOWS_CONTEXT_H
#if defined(_WIN32)
typedef uint64_t sigjmp_buf[32];
__attribute__((returns_twice)) int wasmoon_windows_setjmp(sigjmp_buf env);
__attribute__((noreturn)) void wasmoon_windows_longjmp(sigjmp_buf env, int value);
__attribute__((sysv_abi, returns_twice)) int wasmoon_windows_guest_setjmp(sigjmp_buf env, int save_mask);
#define sigsetjmp(env, save_mask) wasmoon_windows_setjmp(env)
#define siglongjmp(env, value) wasmoon_windows_longjmp(env, value)
#endif
#endif
