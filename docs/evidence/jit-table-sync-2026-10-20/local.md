# Cooperative JIT table synchronization: local evidence

This is local validation of an uncommitted working tree based on
`c61b68303685930a0180f9bc67a3eda32aa8aa29`, whose clean tree matches merged
main commit `38b5c1cfbd3f78596e6dfe694962c845382f835a`. It is not clean CI
acceptance. [local.json](local.json) records source hashes, toolchain, commands,
measurements and coverage. Raw logs remain in ignored `target/issue553` and
`target/sanitizers`.

The original million-iteration cooperative integer loop returns `I32(0)` and
yields 976 times. On macOS ARM64 release builds, an unused 1000-entry function
table increased execution from 3–4 ms to 1658–1887 ms. Independent phase batches
identified full uploads and repeated structural type-graph comparisons as the
main costs. GC setup batches took 0–1 ms; disabling the C heap retained the
slowdown. These batches are controls, not additive timing spans.

The fix caches live-instance type mappings by object identity and records
synchronization checkpoints on the shared runtime table. Runtime writes and all
native writes/growth advance their respective revisions. Completed copies
acknowledge both representations without feedback invalidation. Encoder and
function-binding changes invalidate cached encodings. Host boundaries and
execution admission, GC tracing, cancellation and terminal cleanup remain in
place. Changed tables still require a full copy.

Skipping redundant uploads exposed previously repaired native metadata:
`table.init` must retain the actual function owner's Store type identity,
including imported subtypes, and `table.grow` must initialize callable metadata.
Copyback of non-nullable growth needs a valid new entry as initializer. These
paths have focused regressions. Type cache publication also retains reentrant
Store-close and initialization-scope behavior.

The expanded reproduction uses 40 explicit type declarations with the C heap
enabled. Setup and JIT compilation are outside the measured interval. Builds
complete before three serial benchmark processes, each with three trials.
The clock resolution is 1 ms, and every case checks the same return value and
976 yields.

| Unused function-table entries | Before, ms | After, ms |
| --- | --- | --- |
| 0 | 3–4 | 3–4 |
| 1000 | 1698–1733 | 3–4 |
| 100 | Not measured in this expanded baseline | 3–4 |
| 10000 | Not measured in the baseline | 3–4 |

The original smaller harness separately measured 100 entries at 171–181 ms
before the fix. The after results above belong to the expanded harness; they
are not mislabeled as reruns of the unchanged original harness. There is no
head-to-head Wasmtime benchmark.

Validation includes:

- Strict native/wasm checks with warning 73 denied, formatting, generated
  interfaces and module-boundary audit.
- Full native 2833/2833 and wasm 1347/1347 tests.
- Core JIT, portable native and actual wasm: each 258 files and 62563 assertions,
  zero failed or unsupported cases.
- Three Component suites on both native engines: each 59 files and 1385
  commands, zero failures or skipped commands.
- Full pinned Wasmtime misc execution with high-memory cases included:
  692 passes and 72 assertion-free scripts, zero failures, timeouts, unsupported,
  deferred or harness-error cases.
- Fresh macOS ASan/UBSan closure: 206/206 tests, both ASan positive controls
  detected. All 601 compared copied source files match the working tree.
  LSan is unavailable locally; no Linux leak-detection acceptance is claimed.
- Red/green regressions cover unchanged-table copy avoidance, parked runtime
  mutations, shared native aliases and all bulk mutations, callable registration
  changes, immediate indirect calls after init/grow, imported subtypes,
  non-nullable growth, parked GC roots/cancellation and type-cache reentrancy.

Windows, Linux LSan and final-head CI remain pending submission.
