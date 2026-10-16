# ISS-627 local acceptance

Implementation and verification were performed on macOS ARM64 from parent
`25dac7da3e3b99f98b074d0f3c5d054ffe5ca65d`, on
`milky/unify-runtime-resource-budgets`, with uncommitted changes.
These are local working-tree receipts, not Linux leak-detection or Windows CI
acceptance. No toolchain, release version, remote branch or PR was changed.

The [resource/phase inventory](../../resource-budgets.md) documents units, owners,
admission/release, shared resources, compute controls and isolation limits.
[Local results](local.json) summarize the checks;
[source hashes](source-manifest.json) identify the 91 changed source/interface/
configuration files. All 86 non-configuration source/interface copies in the
isolated sanitizer workspace match these hashes. Its five package configuration
files receive the runner's documented instrumentation transformations.
The fresh CLI's SHA-256 also matches the WASI runner's recorded binary digest.

## Reproduced problems and changes

- Aggregate memory/table admission, growth and native aliases now retain one
  native RC reservation; failed growth leaves usage unchanged.
- GC payloads, retained identity metadata, exception mirrors, extern wrappers,
  continuations, task slots, parked root registrations and native invocations
  have defined ownership and admission. Budgeted GC cannot bypass the common
  allocator through JIT inline allocation. Repeated arrays are admitted before
  their expanded temporary representation is constructed.
- Executable functions and trampolines are admitted before staging. Failed
  replacement preserves the previous installation; rollback returns its new
  reservations.
- Core decoding meters bytes visited and compressed expansion (including locals
  and recursive type placeholders). AST shape/depth is admitted before
  validation/canonicalization. Component binary preflight also runs before
  recursive decoding and embedded Core validation.
- Core/Component scoped execution controllers survive delayed polling and
  repeated suspension. Native Component artifacts have safepoints; pure async
  compute yields to MoonBit cancellation. The public Component facade exposes
  policy and preserves structured resource/compute errors.
- A provisional admission for a small module cannot authorize a different,
  larger validated AST. Foreign, cancelled and consumed tokens remain invalid.

Two integration regressions were found and fixed during the sweep:

1. An initial Core transaction rolled back the function owner of references
   already written into imported tables. `linking.wast` and two multi-memory
   linking files reproduced five failures per engine. Core-owned allocation
   rollback now commits before visible segment initialization. Later traps keep
   those functions/instances and their charge, as required for existing table
   entries to remain callable. The new public-API test also checks retained
   quota and terminal release.
2. Initially, interpreter compute yields were classified as canonical waits.
   `async/same-component-stream-future.wast` then falsely reported deadlock with
   outstanding stream work. `CoreSuspension::CooperativeYield` now remains
   runnable, while genuine canonical waits still require progress and cancel
   on deadlock. A focused scheduler test protects both sides of that boundary.

Component traps retain canonical Store poisoning. Tests reuse the existing Core
instance after interruption, and reuse a shared budget with a fresh Component
runtime after closing the poisoned one. They do not clear poison flags.

Captured positive-control logs have trailing whitespace trimmed.

## Local gates

| Check | Result | Receipt |
| --- | --- | --- |
| `moon info`, `moon fmt`, strict native check | Passed | [native check](native-check.log) |
| Native tests in dedicated target directory | 2721/2721 | [tests](native-tests.log) |
| Strict C compilation | 43 stubs, warnings denied | [C gate](strict-c.log) |
| Module dependency boundaries | Passed | [boundary gate](boundaries.log) |
| Fresh release CLI build | Passed | [build](release-build.log) |
| ASan/UBSan, system allocator | 163/163 | [tests](sanitizer-tests.log), [summary](sanitizer-summary.json) |
| ASan positive controls | Both expected failures detected | [MoonBit allocation probe](asan-positive-control.log), [native stub probe](native-asan-positive-control.log) |
| Core WAST, each engine | 258/258 files; 62563 assertions | [both-engine log](core-wast.log) |
| Component stable 0.2, each engine | 23/23 files; 845 commands; no skips | [native](component-stable.log), [interpreter](component-stable-interp.log) |
| Component async 0.3, each engine | 24/24 files; 153 commands; no skips | [native](component-async.log), [interpreter](component-async-interp.log) |
| Component future-gated, each engine | 12/12 files; 387 commands; no skips | [native](component-future.log), [interpreter](component-future-interp.log) |
| WASI 0.3 HTTP-contract, both engines | 110/110 | [summary](wasi03-summary.json), [log](wasi03.log) |

Core WAST used `python3 scripts/run_all_wast.py --rec --dump-failures`.
Each Component suite used `scripts/run_component_wast.py --suite SUITE`, with
and without `--no-jit`. The pinned `wasm-tools` was 1.254.0.
WASI used the pinned upstream `609c446139956ff30239f87cb18af1dc6128bed2`, the
existing documented HTTP-contract corrections, both engines, and `--jobs 1`.
No guest, timeout, warning or failure expectation was weakened.

The sanitizer runner independently copies source packages and configures
ASan/UBSan through supported package flags. Its scope excludes uninstrumented
MoonBit runtime objects and JIT-generated machine code. On this platform
`leak_detection=false` and `lsan_probe=not_applicable` are expected; they are not
proof of zero Linux leaks.

## Historical local acceptance boundary

ISS-627 stays `in_progress` until Linux native/LSan and Windows Clang/MSVC CI
validate a submitted revision. Existing CI already runs the new public blackbox
fixtures, strict C stubs and isolated sanitizer closure. Linux must prove enabled
leak detection and its independent LSan positive control; both Windows compilers
must pass the native and external suites. No remote acceptance has been claimed
for this working tree.

## Cross-platform CI acceptance

Implementation `076b56a08c58fed1fe20329399cb619df90067f0` passed all five jobs in
[run 38848863428](https://github.com/Milky2018/wasmoon/actions/runs/38848863428).
[The CI record](ci.json) includes job and artifact identities, binary digests and
source merge provenance, independently of the historical local snapshot above.
The clean artifact source merge `c7105d993871a78bdfd8a423a241d938c8f5c802` has
main `25dac7da3e3b99f98b074d0f3c5d054ffe5ca65d` and that implementation head as
its parents.

- Linux ASan/UBSan/LSan: [163/163 ordinary tests](ci-linux-sanitizer-tests.log),
  leak detection enabled, all three positive controls detected, no ordinary
  leak report; the [separate LSan positive control](ci-linux-lsan-positive-control.log)
  detected the intentional 17-byte leak. Instrumentation exclusions remain
  unchanged. The log retains an upstream async C compiler warning about the
  ignored return value of `write`; this is separate from Wasmoon's strict C gate.
- Windows Clang and MSVC: each passed 43 strict C stubs, 2721/2721 native tests,
  and 110/110 external WASI 0.3 HTTP-contract cases. The native probe suites
  each ran 53 tests with three existing privilege-dependent skips; exact reasons
  are retained in the [Clang](ci-windows-clang-probes.log) and
  [MSVC](ci-windows-msvc-probes.log) logs.
- Linux AMD64 and macOS ARM64 completed every job step successfully, including
  external suites and independent-module installation.

Captured CI logs normalize line endings and trim trailing whitespace. ISS-627
is closed with this evidence. The subsequent documentation-only head must pass
all checks again before final PR acceptance; no merge or publication is implied.
