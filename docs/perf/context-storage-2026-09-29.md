# JIT context storage and ownership

Date: 2026-09-29. Tracking: ISS-600. Baseline: `3df319475fcd0e40a5f502b5217b31b03c28573e`.

## Implementation

`jit_context_t` now describes only the 128-byte generated-code prefix. Helper-only declarations live in the private `jit_context.h`. One allocation, `jit_context_owner_t`, contains both the prefix and runtime state; the existing MoonBit external-object finalizer still owns it. Helpers recover the enclosing owner through its initial member. There is no back-pointer load or second allocation for private state.

Bulk-memory/table segment bookkeeping is allocated only for a nonempty segment list and released on reset. A standalone context creates an exception arena only when capturing an exception, and a continuation arena only when defining a continuation type. Binding Store-owned arenas retains the existing sharing/refcount contract without first creating disposable fallback arenas.

Execution state still transfers to/from trap activations on nested calls, suspension and abandonment. GC roots, exception payloads, spilled locals and cancellation callbacks retain their original ownership. Scalar execution bookkeeping remains embedded: splitting each piece into another allocation would add failure paths and indirection to normal entry/exit. This change does not move invocation-local state into shared Store state.

Compiler layouts are initialized once from C `offsetof`/`sizeof` values. Existing fixed-offset tests pin every generated-code field. All prefix offsets and helper call signatures remain unchanged, so existing JIT artifacts remain compatible and the codegen revision is unchanged. A future change to that prefix still requires an artifact revision bump.

This is a storage/encapsulation change, not a dynamically sized Wasmtime-style VMContext implementation. In particular, the old structure already had a 128-byte directly accessed prefix. Hiding the private tail must not be described as reducing that hot prefix by 76%.

## Storage

Measured on macOS arm64; native allocations exclude MoonBit's unchanged external-object wrapper, allocator metadata, backing memories/tables, and Store-owned shared resources.

| Quantity | Before | After |
|---|---:|---:|
| C context interface structure | 544 B | 128 B |
| Generated-code prefix | 128 B | 128 B |
| Context owner, including private inline state | 544 B | 480 B |
| Optional segment bookkeeping | embedded | 64 B when used |
| Owner plus segment bookkeeping | 544 B | 544 B |
| Fresh one-function context: requested bytes | 648 B | 488 B |
| Fresh one-function context: allocation calls | 4 | 2 |
| Matching nonnull frees on destruction | 4 | 2 |

The construction probe wraps native C allocation calls on the actual before/after sources. The old 648 bytes are 544 bytes of context, an 8-byte function-pointer array and two 48-byte arenas. The new 488 bytes are a 480-byte owner and the same 8-byte array. Allocator usable-byte counts are recorded separately in the evidence archive; requested bytes are not RSS.

For a context already bound to shared Store arenas, removing fallback arenas primarily saves transient allocations. Its retained context bookkeeping decreases by 64 bytes if it has no segments; with segments, retained bookkeeping is unchanged and uses one additional allocation. Fully exercised standalone contexts can also recreate both arenas lazily. There is no claim that every workload saves 160 retained bytes per instance.

## Validation

- `moon info`, `moon fmt`, and strict native checking with warning 73 enabled.
- 2,606 native tests passed, including segment-state reset/reuse/isolation and existing nested trap, GC-root, continuation and cancellation tests.
- 37 native C stubs compiled with warnings denied.
- ASan/UBSan: 62 tests passed, plus the runner's instrumentation proof.
- Final core WAST sweep: 258/258 files passed on each engine; JIT reports 62,563 passing assertions and zero failures.
- WASI 0.3 component suite: 24/24 files, 153 commands passed, none skipped.
- Module boundary audit passed.

An earlier sweep hit the existing 20-second timeout on JIT `memory64/table_grow64.wast`; its isolated rerun passed all 21 assertions, and the final complete sweep passed without a timeout. Local validation is macOS arm64; it does not substitute for Windows/Linux CI.

## Measurements

The native lifecycle driver repeatedly calls the real `alloc_context_internal(1)` and `free_context_internal` one million times. Both variants use Clang `-O2`, the same dependency archives and the system allocator runtime; they do not execute guest code or include MoonBit object construction. Allocation-count instrumentation is a separate executable, never used for timing.

Guest measurements use separately built release CLI binaries, alternate AB/BA order, discard one warmup pair and retain every measured pair. AEGIS and hash use verified warm artifact-cache hits. The GC fixture creates and retains the latest of ten million struct objects and returns `9999999`; its artifact is not cached, so both variants compile afresh. Compilation and invocation phase timings are retained. No local build, test sweep or other benchmark overlaps timed runs. Ordinary OS activity is not isolated.

A preliminary version used a private-state back-pointer. A short GC-loop probe was about 2% slower, so the final implementation recovers the inline owner directly. Preliminary results are retained as diagnostic evidence, not mixed with the final samples.

| Final measurement (31 alternating pairs each) | Before median | After median | Median paired change, descriptive bootstrap 95% interval |
|---|---:|---:|---:|
| One million context create/destroy operations | 120.144 ms | 64.470 ms | -45.49% [-45.99%, -44.64%] |
| AEGIS-128L, full CLI wall time | 778.059 ms | 789.834 ms | +0.73% [-0.30%, +1.54%] |
| GC loop, full CLI wall time | 637.195 ms | 633.688 ms | -0.44% [-0.99%, +0.46%] |
| Hash, full CLI wall time | 7.595 ms | 7.410 ms | -2.29% [-4.34%, -0.97%] |

Positive means slower. Paired changes are medians of individual ratios, not ratios of the two marginal medians. Intervals resample paired ratios (10,000 replicates, seed 600); they are descriptive and do not control for multiple comparisons or system drift.

GC invocation medians are 626.056 ms before and 623.823 ms after; compilation is about 0.4 ms. Every GC result is `9999999`. The two substantial guest workloads do not establish a speedup or the earlier GC regression. The hash case is dominated by millisecond-scale process/runtime startup and must not be advertised as generated-code throughput improvement. The clear improvement is native context allocation/destruction; it is not a 45% whole-program speedup.

The allocation probe reports 752 versus 528 allocator-usable bytes on this machine, versus 648/488 requested bytes. These figures include size-class rounding but exclude allocator metadata and still are not RSS.

The final binary successfully loads the baseline AEGIS cache (`cache_hit: true`, exit 0). A separate deterministic memory store/load fixture is freshly compiled and cached by the baseline, then hits that cache with the final binary; both return `42`. AEGIS stdout contains a timer and differs between runs; it is not a correctness oracle.

Raw pairs, compiler commands/drivers, fixture source, binary/source hashes, allocation output and validation logs are retained in [the evidence archive](context-storage-2026-09-29.json.gz). The preliminary back-pointer measurements used a smaller GC fixture and are diagnostic only, not directly comparable to the final ten-million-object GC timings.
