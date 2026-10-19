# Windows HTTP timing interference

The Windows TLS server fixture synchronously imports its PFX credentials on the
same event-loop thread as the HTTP timing tests. A naturally slow
`PFXImportCertStore` can therefore expire another test's deadline before its
ready producer resumes. This is a demonstrated source of intermittent failures
with both Clang and MSVC, not a compiler-specific code-generation failure.

This investigation does **not** establish which operation caused the original
three-second MSVC failure. That run did not record an API timeline. Its exact
pair of errors was reproduced by a controlled synchronous stall; later natural
failures establish the interference mechanism with shorter PFX stalls.

## Original observation

At `9439b780`, [run 39249161277, attempt 1](https://github.com/Milky2018/wasmoon/actions/runs/39249161277/attempts/1)
failed two HTTP tests in MSVC job `118048404823`:

- `consumer backpressure does not consume the next body read budget` raised
  `TimeoutError`. Its direct `HttpInput` read uses `HttpTransportError` for the
  50ms budget; `TimeoutError` identifies the outer 3000ms guard instead.
- `first body byte keeps its budget through headers and chunk framing` received
  an empty body instead of `hi`. This assertion runs after a successful `send`,
  but before checking the trailers that carry transport errors. The old log
  cannot establish the precise transport error from the empty body alone.

The unchanged-SHA rerun passed. That result established successful acceptance
for that attempt, not a root-cause fix.

## Experiments

The generated native test driver runs up to ten async tests on one event loop.
`moon test --no-parallelize` serializes executables, not those async tests.
The TLS trust-verification test and HTTP timeout tests share its whitebox
executable. The fixture calls the pinned async 0.22.4 SChannel server helper,
which invokes `PFXImportCertStore`, certificate lookup and
`AcquireCredentialsHandle` synchronously.

Temporary tracing measured QPC elapsed time, wall-clock time, thread CPU time,
IOCP wait overshoot, body deadline transitions and producer/consumer progress.
Both experiments first built and tested the complete native workspace. They
then repeated four cohorts 300 times per compiler: all whitebox tests, the two
original positive tests, those two plus TLS, and the nine timeout tests alone.

| Diagnostic run | Compiler | Cohort runs | Failed cohort runs | Failed verdicts |
| --- | --- | ---: | ---: | ---: |
| [39262149808](https://github.com/Milky2018/wasmoon/actions/runs/39262149808) | Clang | 1200 | 3 | 3 |
| 39262149808 | MSVC | 1200 | 5 | 5 |
| [39263705985](https://github.com/Milky2018/wasmoon/actions/runs/39263705985) | Clang | 1200 | 10 | 13 |
| 39263705985 | MSVC | 1200 | 1 | 2 |

All natural failures occurred in the complete whitebox cohort. Each other
cohort passed all 300 repetitions per compiler and experiment. The full
workspace runs passed, and the script restored every temporarily patched
source byte. These are explicitly instrumented diagnostic observations, not
clean-source sanitizer or platform acceptance receipts.

## Natural failure timeline

The [Clang backpressure trace](http-timing-natural-backpressure.log) from run
39263705985, repetition 240, records one OS thread (`tid=8908`):

| QPC milliseconds | Event |
| ---: | --- |
| 576209.589 | Consumer's 150ms backpressure sleep returns |
| 576209.605 | Consumer broadcasts readiness |
| 576209.625 | Fresh 50ms body deadline is created |
| 576209.639 | Producer observes readiness |
| 576209.679 | Another test enters TLS server initialization |
| 576288.014 | `PFXImportCertStore` returns after 78.303ms |
| 576289.775 | TLS initialization returns |
| 576289.937 | The 50ms body timeout fires |
| 576289.962 | Producer's write returns |

The deadline is correctly created **after** the consumer returns. Another
test's synchronous call then prevents ready work from making progress before
it expires. The resulting error is the inner `HttpTransportError`, unlike the
outer `TimeoutError` in the original uninstrumented failure.

The [MSVC deadline trace](http-timing-natural-deadline.log), repetition 215,
records a 200ms body deadline at QPC 514127.226, followed by a 513.418ms PFX
import. The deadline fires at 514643.440. Certificate lookup takes 0.005ms and
credential acquisition takes 1.641ms; the large stall is inside PFX import.
Both compilers observed natural PFX calls exceeding 500ms. Their thread CPU
increment was often zero at Windows' coarse accounting resolution. This does
not identify the Windows-internal wait or distinguish it from VM descheduling.

In the preceding experiment, the largest observed IOCP overshoot was about
16ms and the largest consecutive wall/QPC delta discrepancy was below 3ms.
Neither explains the captured hundreds-of-milliseconds stalls. These bounds
apply to those traces and do not retroactively rule out a clock jump in the
original run.

## Exact-signature control and limits

A deliberate 3500ms synchronous delay in TLS server initialization reproduces
both original errors on **both** compilers, while the TLS verification test
itself passes. See the [MSVC control trace](http-timing-injected-stall.log).
The injected run is an expected failure, never an acceptance result.

Natural sampling did not reproduce the original exact pair of an outer
three-second timeout and empty response. It did reproduce the backpressure
test failing from a shorter PFX stall, plus other deadline assertions failing
from the same interference. The cause of PFX latency inside Windows, and the
specific blocking operation in the original run, remain unproven.

The corrective boundary is to keep synchronous TLS server credential setup out
of the event loop that runs HTTP timing assertions: isolate the server fixture
or run it through a suitable blocking-work boundary. Increasing deadlines or
changing the HTTP body-budget contract would not remove the coupling. No such
runtime or test restructuring is included in this diagnostic change.

Temporary workflow steps and tracing code have been removed. Production code,
test assertions, deadlines and the configured toolchain remain unchanged.
[Machine-readable observations and raw/archive hashes](http-timing-diagnosis.json)
retain the experiment heads and selected evidence. The removed probe script
is recoverable at diagnostic commit `ecc611eb`.
