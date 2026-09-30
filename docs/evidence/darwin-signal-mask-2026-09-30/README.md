# Darwin signal-mask shutdown deadlock

## Finding

At the diagnosed revision, Wasmoon's native trap boundary calls `sigsetjmp(activation->jmp_buf, 1)` in `jit_ffi/jit.c`. On Darwin ARM64, the matching `siglongjmp` restores the saved mask through `sigprocmask`. XNU's process-mask implementation updates every thread, overwriting the async signal worker's independently configured mask. This can consume the shutdown wakeup in the ordinary SIGUSR2 handler before the worker enters `sigwait`, leaving the main thread blocked in `pthread_join`.

This is a native trap / signal-thread integration defect. It predates the function-table and globals RC migrations; neither WAST assertion execution nor compilation is stuck. The earlier characterization as an unexplained timeout was incomplete.

## Evidence

Host: macOS 26.7 (25G229), ARM64. Current Wasmoon source: `110e63c2f4c77d2b373c45513bb06497eac1a2dc`; async: 0.22.4.

1. Uninstrumented repeated execution reproduced hangs in both reported fixtures, across the earlier `f3b1e0aa` binary, `fa6602c7`, and the current binary. All four sampled processes were waiting in async shutdown (`pthread_join` versus `sigwait`).
2. A 30,000-process probe run alternated the JIT fixture, the interpreter fixture, and a separate async-only executable. It recorded 30 hangs, all in JIT mode. All remained blocked for over 23 seconds and immediately exited successfully after an extra SIGTERM woke the signal worker. Assertions were already successful. A more detailed 6,000-process run reproduced four additional hangs with the same recovery.
3. Detailed interposition traces show `pthread_kill(SIGUSR2)` returning zero, the ordinary SIGUSR2 handler running, then the worker re-blocking SIGUSR2 and entering `sigwait` with no pending signal. The worker's mask had become the main thread's `0x84003` instead of its own `0x40004003`.
4. Calling the unchanged async C signal-thread implementation for 100,000 start/stop cycles passed, including a variant with the normal dummy SIGUSR2 handler. Adding a main-thread `sigsetjmp(..., 1)` / SIGTRAP / `siglongjmp` reproduced the same deadlock on the first cycle, without MoonBit, Wasm, or JIT-generated code.
5. The independent `mask-proof.c` removes async, signal delivery and timing from the experiment. A worker blocks SIGUSR2 and waits at a condition variable. The main thread performs one nonlocal jump. In five of five runs with `save_mask=1`, the worker's mask changed from blocked to unblocked; five `save_mask=0` controls preserved it.

The original CI run has no thread dump, so its exact blocked instruction cannot be retrospectively proven. The same two fixtures, original executable and failure class have been reproduced locally with the causal chain above. A green rerun does not eliminate this race.

## Deterministic reproduction

```sh
cc -O2 -pthread mask-proof.c -o /tmp/wasmoon-mask-proof
/tmp/wasmoon-mask-proof 1  # exits 1: worker mask changed
/tmp/wasmoon-mask-proof 0  # exits 0: worker mask preserved
```

Expected Darwin ARM64 result:

```text
save_mask=1 worker_SIGUSR2_before=1 after=0
save_mask=0 worker_SIGUSR2_before=1 after=1
```

`traces.json.gz` contains the stress harnesses, sampled stacks, signal probes, C reproducer and the exact async source used (with its license). Temporary absolute paths in the harnesses refer to the diagnosis workspace and should be adjusted when replaying. This is diagnostic evidence, not a portable expectation that every platform must exhibit the Darwin behavior.

## Source confirmation

- [Apple libplatform ARM64 setjmp, pinned revision](https://github.com/apple-oss-distributions/libplatform/blob/2512ffd8bb5c6caff3c8ea83331ab8a0adc820c3/src/setjmp/arm64/setjmp.s#L129): a saved-mask `siglongjmp` falls through to `longjmp`, which calls `sigprocmask(SIG_SETMASK, ...)` and also restores alternate-stack status.
- [XNU set_procsigmask, pinned revision](https://github.com/apple-oss-distributions/xnu/blob/f6217f891ac0bb64f3d375211650a4c1ff8ca1ea/bsd/kern/kern_sig.c#L603): iterates every uthread and replaces its signal mask.
- [Apple pthread_sigmask contract](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/pthread_sigmask.2.html): modifies the calling thread only.

These public source revisions explain the observed behavior; they are not claimed to be a byte-for-byte source match for the installed OS binaries.

## Repair boundary

Repair Wasmoon's Darwin trap landing so signal-mask restoration is thread-local. Preserve repeated synchronous traps, alternate-stack state, nested activation boundaries and continuations. Simply changing `sigsetjmp(..., 1)` to zero is insufficient: the current thread's trap signal mask and alternate-stack bookkeeping still need correct restoration. Do not increase runner timeouts or add polling to hide the deadlock. Async can independently harden its pre-wait cancellation check, but that alone does not stop Wasmoon from overwriting other threads' masks.

The original diagnosis commit did not change runtime behavior. The subsequent repair disables Darwin's process-wide jump-mask restoration, saves/restores the invocation's mask via pthread_sigmask, and returns signal handlers through the kernel before jumping from a recovered invocation stack. This preserves alternate-stack bookkeeping without using private Darwin APIs. Linux and Windows retain their existing jump paths.

The deterministic native regression in `native_test_support/trap_test_support.c` fails before the fix and passes after it. It checks a worker's independently blocked SIGUSR2, the caller mask, repeated alternate-stack SIGSEGV recovery and nested activation recovery. The detailed 6,000-process probe run completes without hangs. Core WAST, async-0.3 and the full misc corpus pass locally. ISS-614 is closed after successful cross-platform CI acceptance.

## Darwin x86_64 follow-up

The updated trap code compiles with strict warnings for Darwin x86_64. An isolated x86_64 build using the installed MoonBit version's scalar runtime (the installed SIMD objects are ARM64-only) runs under Rosetta and passes the new regression, all 191 wasmoon_jit package tests, the 258-file core JIT suite (62,563 assertions), and full JIT misc (346 passes, 36 script-only, no failures/timeouts/deferred cases). The compiler wrapper and results are retained in `fix-validation.json.gz`. This validates the x86_64 recovery path, not production x86_64 toolchain packaging.

## Cross-platform acceptance

[CI run 36663336133](https://github.com/Milky2018/wasmoon/actions/runs/36663336133) passed all five jobs for fix commit `de537e14a9abed5f65570d025b753289b38ce3a8`: macOS ARM64, Linux AMD64, Windows clang, Windows MSVC, and Linux ASan/UBSan. In particular, macOS passed both previously affected external suites and the component gates. The CI metadata is retained in `fix-validation.json.gz`.
