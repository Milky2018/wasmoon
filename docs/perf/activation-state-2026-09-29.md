# Activation-owned native execution state

Date: 2026-09-29. Tracking: ISS-606, part of ISS-602.
Baseline: `f55a1f154e5135eee52c8c0550ab9bad9c43c32b`.

## Ownership change

Exception handlers, payloads, spilled locals, precise root/frame chains, scratch roots and collection flags now belong to a native activation. The instance holds a borrowed pointer to the currently bound state. Nested entry installs another state; detach restores the previous pointer; attach captures the actual resuming caller. Abandonment releases the parked activation directly without temporarily overwriting a surviving instance's state.

This layer remains native C because it participates in setjmp/longjmp, signal handling and native fiber stacks. It is not a migration of these native control-flow primitives into MoonBit. The existing MoonBit-managed context/fiber handles still own their native resources: normal return releases activation resources, and cancellation/fiber finalization releases parked resources before unmapping the native stack. No new public raw-pointer seam or reverse callback was introduced.

The activation record is allocated by the caller of the function containing setjmp. This avoids relying on modified automatic locals of that function after longjmp. Trap frames are captured before returning from the catching function.

Standalone context helper calls lazily allocate a 96-byte execution state, freed by context teardown. Explicit standalone scratch roots seed a fresh activation through a copy; nested calls start with independent scratch. Updating an invocation no longer overwrites standalone roots. Retaining the standalone state across invocation is intentional compatibility behavior.

The context's module metadata, continuation/exception arenas, hostcall/cancellation configuration and scheduling controls remain separate. Module-shaped generated layouts and control configuration migration are not completed here. ISS-602 stays open.

## Confirmed defect and regression coverage

A new scratch-isolation test fails on the pinned baseline: an inner activation overwrites the outer activation's scratch roots. Parked registrations also omitted scratch roots. The refactor both isolates these arrays and includes them when registering parked roots.

Tests now cover nested replacement, detached abandonment while another invocation is active, scratch-only GC retention, release after completion, restoring the actual resuming caller (including the generated debug slot), and standalone root seeding without aliasing. Existing continuation tests exercise suspension, cancellation, nested exception handlers and precise GC roots.

## Storage accounting

Measured with the same macOS arm64 C headers/toolchain for both revisions:

| Struct payload | Before | After |
|---|---:|---:|
| Per-instance owner | 440 B | 352 B |
| Per-activation record | 1,008 B | 1,048 B |
| Generated-code context prefix | 128 B | 128 B |
| Lazily allocated standalone execution state | inline in owner | 96 B |

One instance plus one activation's struct payload changes from 1,448 to 1,400 bytes. This is **not** a measurement of total stack-frame size, RSS, allocator headers or peak process memory. The catching helper introduces another native call frame, which is not included in these struct sizes. A standalone-helper-only instance uses 352 + 96 = 448 bytes rather than 440 bytes, plus one allocator allocation. A standalone-root-seeded invocation also retains that fallback state and a private scratch copy. Numeric invocation state needs no separate heap allocation; its record is on the native stack. Heap-allocated exception/root buffers retain their existing allocation strategies.

Generated offsets do not change, so the artifact version is unchanged. Both directions of cross-version cache loading were executed with cache-hit reports; new code reads baseline caches and the baseline reads caches made after the migration.

## Performance

Local macOS arm64, MoonBit 0.1.20260920 / moonc v0.10.14+7d59c7ec9. Each workload has 31 retained before/after pairs following warmup, with alternating order and no concurrent build/test workload. Values are end-to-end CLI wall time, including process startup, parsing and (for WAST) compilation. AEGIS samples all verify warm-cache hits. These are not isolated instruction-cost measurements.

`indirect` is the existing 10-million-call fixture. `gc` allocates one million one-field structs; `exceptions` throws/catches one million tagged exceptions. Both assert their final result. `aegis` is the existing algorithm fixture. The table shows per-version medians and the median paired change with a percentile bootstrap interval; the paired estimate need not equal the ratio of independent medians.

| Workload | Before | After | Paired change [95% interval] |
|---|---:|---:|---:|
| indirect | 289.015 ms | 297.135 ms | +1.28% [+0.28%, +2.04%] |
| gc | 55.670 ms | 56.082 ms | +0.94% [+0.24%, +1.47%] |
| exceptions | 132.835 ms | 130.184 ms | -2.66% [-3.37%, -1.15%] |
| aegis | 840.973 ms | 826.349 ms | -0.96% [-3.02%, -0.68%] |

The first candidate showed roughly +4% paired time on the exception-heavy fixture. Repeated execution-state lookups inside individual exception helpers were replaced with one local state pointer per helper. The initial samples and executable hash are retained as well as the final measurements. These sessions do not establish a hardware placement cause, and small changes in the table should not be presented as general throughput improvements.

## Validation

- Pinned baseline scratch-isolation regression: 1 failed, confirming the old behavior.
- 2,613 native tests passed, including two added regressions.
- 68 ASan/UBSan tests passed with positive instrumentation controls.
- Strict native MoonBit check with warning 73 enabled and warnings denied.
- 38 C stubs compiled with warnings denied; module boundary and JIT lifetime checks passed.
- Core WAST: both engines pass 258 files, 62,563 assertions each.
- Async 0.3 component WAST: 24 files, 153 commands, no skips.
- Bidirectional cross-version artifact cache hits verified.

The new commit's cross-platform CI status is separate from local validation. See ISS-606. Raw samples, fixture/probe sources, validation logs, binary hashes and source diff are retained in [the evidence archive](activation-state-2026-09-29.json.gz).
