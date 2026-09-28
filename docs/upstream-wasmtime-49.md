# Wasmtime 49.0.1 reference refresh

## Pinned tools and source

The current reference release is Wasmtime **49.0.1**, released 2026-09-24,
commit `46c23a87dac1465986a8ad53ba6a7ae49372857b`, with Cranelift **0.136.1**.
This updates the local performance reference from a 40.0.0 development build
at `68a6afd4f` and the component differential oracle from 45.0.0.

The official archive installer pins SHA-256 digests from the release assets for
Linux x86-64 and macOS arm64/x86-64. The local macOS arm64 archive was downloaded,
verified, and installed in `~/.cargo/bin/wasmtime` and the default component
oracle directory. Previous executables are preserved under
`target/wasmtime-reference-backup`. The adjacent upstream checkout is clean at
the immutable release tag; remote branches were fetched, including development
`main`. The moving upstream `dev` tag was not force-replaced.

Historical performance reports retain their original versions and results.
New evidence belongs to this release and must not be relabeled as evidence for
an older baseline. CI now installs the pinned oracle and executes the component
differential suite on Linux AMD64 and macOS ARM64, uploading its raw evidence.
The installer, shared harness version, audit manifest, tests, and active security
documentation all refer to 49.0.1.

## Corpus refresh

The previous P1 and misc pin, `668016926adfd1b8a79dbce894f1e203d8892599`, was
actually a September 2026 development snapshot, not the old 40.0.0 compiler
reference. Comparing the complete inventories and every vendored byte against
49.0.1 found **no changes** to these corpora, including the retained host-reference
files. Their manifests now explicitly identify release 49.0.1 and its commit;
the per-file hashes are unchanged:

- P1: 58 programs, 63 total tracked source/license/reference files.
- Misc: 382 WAST scripts, four auxiliary WAT files, 395 total tracked files.

This is a provenance refresh, not a claim of hundreds of newly added regressions.
The latest development branch has further changes and proposal tests; those are
not silently mixed into this stable-release baseline. The separate Component
Model specification and wasi-testsuite revisions remain independently pinned.

## New release regressions

The 49.0.1 source adds three test programs relative to the previous snapshot:

- [`p2_file_settime_overflow.rs`](https://github.com/bytecodealliance/wasmtime/blob/v49.0.1/crates/test-programs/src/bin/p2_file_settime_overflow.rs)
- [`p3_file_settime_overflow.rs`](https://github.com/bytecodealliance/wasmtime/blob/v49.0.1/crates/test-programs/src/bin/p3_file_settime_overflow.rs)
- [`p2_http_outbound_body_write_backpressure.rs`](https://github.com/bytecodealliance/wasmtime/blob/v49.0.1/crates/test-programs/src/bin/p2_http_outbound_body_write_backpressure.rs)

The timestamp cases are adapted into a public host-interface test. It supplies
the upstream overflowing seconds/nanoseconds through both P2 and P3 interfaces,
checks both access and modification timestamps, and exercises both `set-times`
and `set-times-at`: eight error assertions in total. Before the fix, Wasmoon
returned `invalid`; it now returns the correctly indexed `overflow` error when
a typed timestamp cannot be represented by the native timestamp conversion.
This is a narrow error-classification fix, not a redesign of timestamp storage.
The regression failed against the original implementation and passes afterward.

The HTTP case's write-permit invariant is adapted to our shared P2 output-stream
interface using a captured stdout sink. The test obtains the actual permit,
submits one byte more, requires a trap, and verifies that no data reached the
host callback. Existing code already satisfies this invariant. This is explicitly
**not execution of the upstream P2 HTTP guest**, nor proof about every HTTP body
resource; the existing P3 HTTP service/client suite is also run separately.

These tests are ordinary native tests, so the existing Linux, macOS, and Windows
native CI lanes include them. Upstream execution-fuel tests are not newly claimed
as coverage; the previously agreed `p1_cli_hostcall_fuel` exclusion remains.

## Acceptance

Local validation uses macOS arm64 and the final rebuilt Wasmoon CLI. Machine-
readable evidence is stored alongside this report; detailed local trial logs are
under `target/upstream-49`.

- Warning-denied native check, formatting and generated interface checks pass.
- 2,586 native tests pass, including the new host contract regressions.
- Core WAST: 258/258 files pass per engine.
- Component stable/async/future suites: 845/153/387 commands pass per engine,
  with no failures or skips.
- Component differential against Wasmtime 49.0.1: 39/39 pass.
- Wasmoon P1 capabilities profile: 116 pass; two hostcall-fuel executions remain
  not applicable. No failures, timeouts, or unsupported cases.
- Wasmtime P1 upstream profile: 55 pass, three per-preopen permission cases are
  unsupported by the reference CLI harness, and one hostcall-fuel case is not
  applicable. These omissions are not counted as passes.
- Misc: 692 assertion-bearing passes and 72 successfully executed script-only
  cases; no failures, timeouts, exclusions, or high-memory deferrals.
- WASI 0.3: 106 pass, four raw failures remain the existing `http-fields` and
  `http-request` WIT expectation differences, once per engine. Fingerprint-based
  acknowledgement passes without hiding the failures. The initial attempt
  lacked the upstream runner's `colorama` dependency and recorded 110 harness
  errors; installing the upstream requirements in an isolated venv resolved it.
- HTTP end-to-end tests pass in both engines, including concurrency, framing,
  trailers, capability denial, and repeated disconnects.
- Python harness tests: 174 tests, 54 platform-dependent skips, no failures.
- Native sanitizer validation: 61 tests plus ASan/UBSan positive controls,
  resolver lifecycle and event-loop checks pass.
- Component security and module boundary checks pass.

## Performance interpretation

The algorithm comparison uses 70 real modules, one cold isolated-cache run per
engine and workload, with `-C parallel-compilation=n` for Wasmtime. It is a new
reference snapshot, not a statistical claim that either engine became faster.
The numeric guest output is a workload timing metric; ratio thresholds classify
performance gaps, not semantic mismatches. Execution errors and missing fresh
compilation evidence remain separate failures. No compilation, tests, or
profiling jobs overlap the comparison.

All **70/70** workloads complete without execution or measurement failures:
34 meet the existing thresholds and 36 are classified as performance gaps.
The thresholds remain 1.05 for the guest timing ratio and 2.0 for the wall-time
ratio. All Wasmoon runs report fresh compilation and no cache hit.
See the [complete comparison](evidence/wasmtime-49-2026-09-28/algorithms.md),
[raw measurements](evidence/wasmtime-49-2026-09-28/algorithms.json), and
[tool/binary provenance](evidence/wasmtime-49-2026-09-28/manifest.json).

No compiler optimization is included in this update. Further optimization work
should compare against this baseline and retain the same measurement controls.
