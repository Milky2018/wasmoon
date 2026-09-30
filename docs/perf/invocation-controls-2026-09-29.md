# Invocation-owned cancellation and scheduling controls

Date: 2026-09-29. Tracking: ISS-609, part of ISS-602.
Baseline: `951b7b1f5ab14138067001178159155fb4501310`.

## Ownership and semantics

Contexts now store control defaults. On entry, a native activation snapshots the configured cancellation callback and scheduling budget, retaining the MoonBit capture. Independent nested entries have separate budgets. Clearing or replacing a context's defaults affects subsequent invocations, not active or parked invocations. To cancel an existing invocation, update the signal captured by its callback; callback captures remain live and mutable.

Guest continuation entry inherits the current caller's control view. On reattachment it selects the actual resuming caller, rather than preserving a borrowed view into a caller that may have returned. Root invocations keep their own snapshot when resumed inside another invocation. Both cancellation polling and atomic wait consult this view. Pop and abandonment release the activation's retained capture. Standalone helpers still consult context defaults.

The activation snapshot is native because it must survive native stack suspension and trap unwinding without retaining a MoonBit callback frame. Its callback is a MoonBit-owned closure with explicit RC retention. No new control heap allocation, C-owned callback copy or raw integer handle is introduced.

## Storage

A compiled local macOS ARM64 probe measures:

| Object | Before | After |
|---|---:|---:|
| Context | 352 bytes | 352 bytes |
| Generated prefix | 128 bytes | 128 bytes |
| Native activation | 1,048 bytes | 1,072 bytes |

The extra 24 bytes store the activation's own control snapshot. One existing control-context pointer becomes a control-view pointer. Generated offsets and artifact format remain unchanged. Context defaults remain necessary for the public setup API and standalone helper compatibility. Module-shaped context layout remains separate work.

## Validation

A focused regression covers independent reentry, shared continuation budgets, restoring the actual caller after suspension, root snapshot isolation, clearing context defaults while parked, and exact capture finalization on pop/abandonment. Existing controlled atomic-wait tests exercise cancellation of an indefinitely blocked wait.

The first incremental native build crashed with SIGSEGV after private C struct layout changes. A clean build of identical implementation code passed the complete suite and a freshly built sanitizer suite. This is consistent with stale native objects; no crash backtrace was retained, so the precise original cause is not established. The reported validation uses the clean build.

## Results

- 2,617 native tests and 71 ASan/UBSan tests passed.
- Strict MoonBit check (including warning 73), 38 strict C compilation checks, existing lifetime and module-boundary checks passed.
- Core WAST: 258 files, 62,563 assertions per engine; async component WAST: 24 files, 153 commands, no skips.
- Cross-platform CI for the current commit is pending separately.

## End-to-end comparison

Same fixtures as the preceding reports. Each workload has 31 retained paired samples after warmup, alternating order, with no concurrent build/test workload. CLI wall time includes startup and WAST compilation. AEGIS samples verify cache hits. The baseline executable hash matches the preceding report's tested executable.

| Workload | Before | After | Median paired change [95% bootstrap interval] |
|---|---:|---:|---:|
| indirect | 242.568 ms | 242.601 ms | +2.32% [+1.60%, +4.17%] |
| gc | 49.625 ms | 50.357 ms | +1.20% [+0.73%, +1.88%] |
| exceptions | 112.514 ms | 115.436 ms | +1.04% [+0.13%, +3.39%] |
| aegis | 730.918 ms | 732.980 ms | +0.24% [-0.01%, +0.75%] |

These measurements do not isolate invocation-entry overhead or cooperative polling cost and do not establish a cache/allocator cause. They must not be generalized into a speedup claim. Raw samples, validation logs, probe source and source/binary hashes are archived in [the evidence archive](invocation-controls-2026-09-29.json.gz).

The indirect, GC and exception paired intervals are above zero in this run. Their small observed regressions remain unresolved and are tracked in ISS-610; they are not dismissed as noise.
