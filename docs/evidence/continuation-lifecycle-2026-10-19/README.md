# Continuation lifecycle migration (ISS-638)

Local macOS ARM64 evidence, 2026-10-19. Base `c23e918d` (merged PR #541),
working branch `milky/migrate-continuation-lifecycle`. These are uncommitted,
dirty-source receipts, not Linux LSan or Windows acceptance. The stable
MoonBit toolchain remains `0.1.20261012` / `v0.10.15+943464bfa`;
`wasm-tools` is `1.254.0`.

## Ownership and scope

See the [transition and ownership inventory](../../native-runtime-policy.md).
MoonBit now owns monotonic one-shot identities, lookup/consumption, marks,
heap-specific sweep, retirement, sealing and pending-work admission. Packed
unboxed metadata borrows addresses only while the RC storage table owns the
physical bodies. The C identity table, manual arena/body reference counters,
mark bits, retired-body linked list and quota-admission decisions are deleted.

Native bodies are RC external objects. Storage and active native cancellation
scopes hold separate references. A failed scope allocation releases its
transferred pin before a trap; a switch target remains pinned across forwarding.
Binding and resume preparation return errors to cleanup rather than jumping
past their owners. Clear first closes all stacks, then drops table owners, so
nested scope pins cannot outlive a freed table entry. Final body release returns
the accepted pending-work unit exactly once.

C retains native stack/fiber operations, handler table matching/control transfer,
physical input/output buffers and immutable machine-call descriptors. These
must not suspend a MoonBit frame. Closed `FuncRef` callbacks return statuses
before native trap/yield/switch. The generated release adapters were inspected:
creation requests are borrowed `void *` views, handle rows are inline structs,
and the take callback performs no state/request retain/release. Context layout
was not expanded for this migration. C line count alone is not a useful measure
of completion: the replacement includes physical RC adapters and explicit
failure cleanup.

## Reproductions and negative controls

1. `root-lease-before.log`: a negative continuation ID contains the exception
   tag bit. Old root unregistration decrements the exception lease count and
   wrongly allows a second exception arena to bind while the first has a live
   snapshot (`1152921504606846977 != 0`). The independent root-kind repair passes
   `root-lease-fixed.log`. Explicit, idempotent owner-kind counters now separate
   the borrowed exception and continuation adapters.
2. `scope-original-refined.log`: the final allocation-failure matrix, executed
   against exact original `c23e918d` production sources, leaves one pending-work
   unit after dropping the guest global and collecting. The fixed matrix passes
   as part of the final native and sanitizer runs. Injection occurs inside a
   guest hostcall, with attempts 1 through 8 and a healthy reuse call each time.
3. Binding a suspended continuation uses attempts 1 through 6, drops any
   remaining global, collects, verifies zero pending work and a healthy call.
   `bind-failure-fixed.log` records the focused run. Removing its native failure
   cleanup makes `bind-cleanup-negative.log` fail with one leaked unit.
4. Removing the transferred-lease release on scope-allocation failure makes
   `scope-cleanup-negative.log` fail with one leaked unit. Both mutations are
   restored; `cleanup-restored.log` and `negative-controls.json` record success
   after restoration. No diagnostic instrumentation remains in production.

An earlier scope fixture retained its guest global and could fail before the
continuation was consumed, at generated root-scope allocation. That observation
was not a valid leak reproduction. It was corrected before the independent
baseline check above. Intermediate logs from that invalid fixture are not used
as acceptance evidence.

## Local validation

| Check | Result | Receipt |
| --- | --- | --- |
| `moon info`, `moon fmt`, strict native warning check | Pass | Generated interface/source diff reviewed |
| Native tests | 2738/2738 | `native-final.log` |
| Native C warnings denied | 43 stubs | `strict-c-final.log` |
| Fresh isolated ASan/UBSan | 175/175 | `sanitizer-tests.log`, `sanitizer-summary.json` |
| ASan/native-ASan expected-failure controls | Both detected | `sanitizer-probe.log`, `sanitizer-native-probe.log` |
| Python scripts | 172 tests, 54 platform skips | `script-tests.log` |
| Core WAST, both engines | 258 files, 62563 assertions per engine | `core-wast.log` |
| Component stable/async/future-gated, both engines | 59 files, 1385 commands per engine, no skips | Six `component-*.log` files |
| Wasmtime misc `stack-switching*`, both engines | 46 files/75 assertions per engine; 92 pass, zero failures/timeouts/unsupported/deferred/skips | `wasmtime-stack.json` |

The native test log contains expected diagnostics from negative CLI tests; its
final result is zero failed tests. MacOS sanitizer reports `leak_detection=false`
and LSan `not_applicable`, not enabled Linux leak checking. No blanket sanitizer,
warning or test exclusion was added. Platform-empty objects retain existing
`libtool` diagnostics; the strict C gate denies source warnings.

`source-manifest.json` records exact changed-source hashes and matching fresh
sanitizer source/test copies. `install.sh` builds in a fresh private directory.
The external suites used the first fresh candidate build; the final benchmark
build followed EOF whitespace normalization only. Both hashes are recorded,
rather than treating differing binaries as identical receipts. Presentation
trailing whitespace is trimmed in archived text logs; numerical data and source
hashes are preserved.

## Isolated performance comparison

Normal release CLI binaries, no relinking or source instrumentation. The saved
before binary matches the accepted exception investigation's final CLI hash;
all 18 source hashes in that receipt match `c23e918d`. The after binary is a
fresh release build of the manifest's dirty source. Raw samples, exact binary
and fixture hashes and paired bootstrap intervals are in `performance-final.json`.

`measure.py` runs 21 shuffled paired serial rounds after two warmups, seed 638.
No other build, test, debugger, profiler or benchmark ran concurrently. A
child-only macOS `DYLD_INSERT_LIBRARIES` interposer counts exactly two native
`putchar` calls and captures thread CPU time plus process retired
instructions/cycles. The interval excludes loading, compilation and teardown,
but includes the fixed boundary envelope. There is no core/frequency control,
cache-miss measurement or cross-platform claim. ISS-640's existing
`spectest.print_char` argument bug is deliberately irrelevant to the counter:
call order identifies the boundaries. Guest `assert_return` independently
checks every iteration count and the bound continuation's final result.

- `bind-N.wast`: repeated zero-argument `cont.bind` on one body, isolating handle
  churn from stack switching; final resume checks 42 outside the interval.
- `suspend-N.wast`: repeated actual resume/suspend operations on one native
  stack, returning the expected iteration count.

CPU medians in milliseconds; the change column is the ratio of the two
medians, while raw JSON also reports the paired-ratio median and its interval.

| Case / iterations | Before ms | After ms | Change | Retired instructions before / after |
| --- | ---: | ---: | ---: | ---: |
| bind-10 | 0.0059 | 0.0059 | +0.0% | 46,137 / 46,535 |
| bind-100 | 0.0262 | 0.0215 | -18.0% | 355,708 / 321,379 |
| bind-1000 | 0.2713 | 0.1167 | -57.0% | 5,775,994 / 2,761,396 |
| bind-10000 | 14.1475 | 1.0556 | -92.5% | 327,430,820 / 27,160,334 |
| bind-30000 | 118.7540 | 3.2550 | -97.3% | 2,782,556,249 / 81,380,236 |
| suspend-10 | 0.0112 | 0.0114 | +1.5% | 77,939 / 80,843 |
| suspend-100 | 0.0398 | 0.0355 | -10.8% | 524,535 / 477,183 |
| suspend-1000 | 0.3616 | 0.2087 | -42.3% | 7,079,409 / 4,158,011 |
| suspend-10000 | 15.0049 | 1.9398 | -87.1% | 340,221,766 / 40,125,220 |
| suspend-30000 | 121.9848 | 5.8540 | -95.2% | 2,822,403,502 / 120,202,409 |

The ten-iteration samples are dominated by short-interval noise: paired CPU
confidence intervals cross one for both workloads. They establish no reliable
small-call speedup or slowdown. At 100 to 30000 iterations the sampled
improvement grows with workload size. Native source inspection identifies the
old quadratic work: `take_continuation` first binary-searches the handle, then
linearly rescans historical rows just to invalidate that same identity. The
managed implementation consumes the found index once and compacts dead rows
at capacity boundaries. The growth of old versus new retired instructions
supports this algorithmic explanation. Do not attribute every cycle saved to
an individual FFI call or speculate about cache behavior from these counters.
No layout tuning or duplicate C fast path was introduced.

Reproduce on macOS with separate saved release binaries and no concurrent work:

```sh
clang -O2 -dynamiclib store-boundaries-dylib.c -o /tmp/continuation-boundaries.dylib
python3 measure.py /absolute/before /absolute/after . \
  /tmp/continuation-boundaries.dylib /tmp/continuation-performance.json
```

## Remaining migration and acceptance

- ISS-638 still requires Linux ASan/UBSan/LSan and Windows Clang/MSVC acceptance
  of these new paths. Its local implementation and measurements are complete.
- ISS-636's remaining review is the GC prepare/finish/abort protocol: native
  root gathering, managed reachability, exception/continuation sweep ordering,
  visitor reentry/failure and rollback need one explicit coordinator. The
  allocation retry policy itself is already migrated. Keep native stack-map
  decoding and physical payload scans as machine primitives.
- ISS-639's layout move is already implemented; reconcile its final archive and
  platform receipts with PR #541 instead of moving the same files again.
- ISS-634 remains an upstream MoonBuild/n2 dependency-tracking problem. Prepared
  patches are not delivered upstream and installed stable is unchanged. Fresh
  release/sanitizer builds are controls, not an incremental-build fix.
- ISS-640 is the separately tracked builtin argument-routing defect; this task
  neither changes nor claims to fix that ABI path.

No continuation migration PR has been created or submitted in this turn.
