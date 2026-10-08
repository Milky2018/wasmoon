# ISS-567: original-fixture shutdown deadlock verification

## Conclusion

The original `simd/load_splat_out_of_bounds.wast` reproduces the Darwin
signal-mask shutdown deadlock fixed by ISS-614. Close ISS-567 as covered by
`de537e14a9abed5f65570d025b753289b38ce3a8`; no additional runtime repair is needed.

This conclusion comes from fresh local reproduction of the original source and
fixture, thread samples, signal traces, and an isolated backport of the repair.
It does not claim to recover the missing stack of the historical CI process.

## Versions and method

- Host: macOS 26.7 (25G229), ARM64.
- Old source: `8d950c08d19ab90525d3cb83331cc68ddf4ac833`, with its declared
  async 0.21.2 dependency. Rebuilt using installed MoonBit; not the original CI
  executable or a recreation of the historical compiler environment.
- Current source: `f753da2c9b750523b4ecc4de1843709ae7624878`, async 0.22.4.
- Original and current fixture SHA-256 both equal
  `ce34f9e56c6aa9d994472124e38c69dd509ea851abe3695781f5eee5e987ad94`.
- Release native builds. Eight concurrent subprocesses per repetition series.
  Each executes the unchanged WAST through `wasmoon test`; interpreter controls
  add `--no-jit`. Every successful process must report two passes, zero failures,
  zero skips, and exit zero.
- Capture a thread sample when a process exceeds two seconds, but retain it
  through the original 120-second timeout. Only then send one diagnostic
  SIGTERM and record whether shutdown completes. This signal is a diagnosis
  step, not a passing result or a production workaround.
- Stop scheduling new repetitions when a slow process is found; already
  running processes complete. Failure counts are observations, not comparable
  estimates of race probability between runs.

## Results

| Runtime | Observation | Successful runs | 120-second timeouts |
| --- | --- | ---: | ---: |
| Original JIT | No interposition | 6,474 | 1 |
| Original JIT | Signal interposition | 3,180 | 2 |
| Original interpreter | No interposition | 10,000 | 0 |
| Original JIT + ISS-614 repair only | Signal interposition | 10,000 | 0 |
| Current JIT | No interposition | 10,000 | 0 |
| Current JIT | Signal interposition | 10,000 | 0 |

The isolated backport keeps the old MoonBit sources and async 0.21.2 unchanged.
Only the three C runtime files changed by ISS-614's repair are patched. The old
trap activation is a stack value rather than the later pointer, so the original
patch's `activation->` accesses are mechanically adapted to `activation.` in
`jit.c`. The complete applied diff is archived as `backport.patch`.

All three timed-out processes were sampled before intervention. Main was in
`moonbitlang_async_terminate_signal_handler` -> `pthread_join` -> `__ulock_wait`;
the worker was in `sigwait_thread_worker` -> `sigwait` -> `__sigwait`.
All remained alive for at least 120 seconds and exited zero within 10 ms of the
additional wakeup. Their flushed output reports both WAST assertions passing.

Both instrumented failures show this order:

```text
main restores its own mask to 0x84003 after creating the signal worker
pthread_kill(worker, SIGUSR2) returns 0
SIGUSR2 HANDLER RAN
worker sets its mask: before=0x84003, after=0x40004003
worker enters sigwait: mask=0x40004003, pending=0
[120-second deadline; diagnostic SIGTERM]
worker wakes with SIGTERM; process exits 0
```

The worker should retain `0x40004003`, including SIGUSR2, independently of main.
The original trap recovery overwrites it with main's `0x84003`; the shutdown
wakeup runs the ordinary handler before the worker starts waiting. The worker
then waits for a signal that has already been consumed. This matches the
[independent mask proof and repair](../darwin-signal-mask-2026-09-30/README.md).
The fixed trace preserves the worker mask and consumes SIGUSR2 in `sigwait`.
The unchanged original interpreter and the old-source repair control separate
this failure from a generic async shutdown defect or a later dependency update.

## Regression acceptance

- Current deterministic native regression:
  `moon test modules/wasmoon_jit --target native --filter 'trap recovery preserves thread masks and alternate signal stack'`
  passes 1/1. This existing regression covers independent thread masks, repeated
  alternate-stack signal traps and nested trap activations. Its original
  before-fix failure is retained in ISS-614's evidence.
- The existing misc runner, using the freshly built current CLI, the exact
  fixture filter, both engines and `--timeout 120`, reports two passing entries,
  zero failures, timeouts, skips or deferred cases.
- No assertion, timeout, corpus file or runtime source was changed in the
  project. No fresh full-corpus or cross-platform CI run is claimed here;
  ISS-614 separately records the repair's successful cross-platform CI.

## Evidence and replay

`evidence.json.gz` contains toolchain metadata, source/binary/fixture identities,
build logs, the unchanged fixture, all per-process timing/exit records, sampled
stacks, signal traces, the interposer source, repetition harness, backport patch,
and focused regression/runner output. Extract its `files` object to a temporary
directory to inspect or replay it. Recorded absolute paths identify this local
run and must be adjusted when replaying.

```sh
cc -dynamiclib -O2 probe.c -o probe.dylib
python3 repeat.py /absolute/path/to/wasmoon /absolute/path/to/fixture.wast plain --runs 10000
python3 repeat.py /absolute/path/to/wasmoon /absolute/path/to/fixture.wast probed --runs 10000 --probe /absolute/path/to/probe.dylib
```

The first plain-run harness matched one literal space after `Passed:` and
`Failed:`, whereas the CLI emits two. It initially mislabeled the 6,474
successful exits as failures. All archived result blocks and zero exit codes
were subsequently checked with whitespace-tolerant matching; original and
corrected records are both retained (`results.jsonl` and
`verified-results.jsonl`). Later runs used the corrected matcher. The timeout,
thread sample and recovery evidence are unaffected by this reporting mistake.
