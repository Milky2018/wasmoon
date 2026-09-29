# Store-wide callable metadata sharing

Date: 2026-09-29. Tracking: ISS-601. Baseline: `77d901d052bb8aa0306869f064f60a2185bfdf7b`.

## Finding and ownership

`StoreTypeRegistry` owns a Store-wide canonical parent graph and native function-address/type map. Previously `bind_native_callable_view` installed one closure per JIT instance; every publication invoked all closures. Each context setter copied four arrays: the same Store parents and entries, plus that instance's unchanged local type and tag mappings. Native storage for the Store-wide arrays therefore scaled with both Store size and bound context count.

The normal JIT path now binds one RC-managed `NativeCallableRegistry` per Store. It owns only the parent and entry arrays. Each context retains that object and keeps its own local type/tag arrays; publication replaces the two shared arrays once, after both allocations succeed. There are no callbacks to rebind contexts on publication. The registry contains no reference to the Store, contexts or executable code; existing Store callable-owner leases continue to keep code alive. Closing the Store clears the shared arrays, and a closed Store cannot create another registry.

The existing public standalone context setter still works by constructing a private registry. The legacy Store callback API remains available for callers, but the built-in JIT path does not register those callbacks. Stores remain serialized execution domains; this change does not introduce concurrent updates during guest execution.

The native registry type and its lifecycle live in `wasmoon_jit/native/callable`. Context binding stays beside the private native context implementation in `jit_ffi`; the shared C header is within the same MoonBit module. Public imports are reexported from `wasmoon_jit`.

## Storage and publication work

On macOS arm64, the context owner decreases from **480 to 456 bytes**. Its generated-code prefix is still **128 bytes**, with unchanged offsets and artifact revision. A shared registry adds one 24-byte managed payload plus its MoonBit external-object header per Store. For one bound context, those 24 bytes cancel the context's 24-byte reduction before accounting for the new object's header/allocation. This is not a universal single-instance memory saving.

A native probe uses 64 contexts, each with 32 function slots, four local type mappings and one tag. The shared Store has 256 types and 2,048 function entries. It calls the actual before/after native implementations, wraps native C allocations for counts, verifies the lookup checksum and releases every context.

| Native C allocations in the probe | Before | After |
|---|---:|---:|
| Initial requested bytes | 2,211,072 B | 80,640 B |
| Initial allocation calls | 384 | 258 |
| Allocation calls for one complete publication | 256 | 2 |
| Total allocation calls, including one publication | 640 | 260 |
| Matching nonnull frees | 640 | 260 |

These counters exclude MoonBit runtime allocations: the unchanged managed context wrappers, the new shared registry payload/header, and the temporary MoonBit arrays used by high-level callers. They are requested bytes, not RSS or allocator usable sizes. The new shared payload adds 24 bytes to the after figure before its header. The large saving is specific to multiple contexts sharing a sufficiently large Store map. At the high-level API, conversion of the Store arrays also happens once per publication instead of once per context; the C probe does not count that additional saving.

## Timing and limitations

Both binaries use the same release toolchain and are measured serially on the same macOS arm64 machine. Each comparison alternates AB/BA order, discards one warmup pair and retains 31 pairs. No build or test runs overlap the measurements. Percentages are medians of paired ratios, not ratios of medians. Intervals below are descriptive 95% bootstrap intervals (10,000 resamples), not guarantees across machines.

| Workload | Before median | After median | Paired time change | Interval |
|---|---:|---:|---:|---:|
| 1,000 native metadata publications, 64 contexts | 28.063 ms | 0.378 ms | -98.64% | -98.66% to -98.62% |
| WAST: 10 million subtype-checked indirect calls | 237.04 ms | 228.78 ms | -4.01% | -5.42% to -1.89% |
| AEGIS-128L, warm artifact cache | 708.07 ms | 714.70 ms | +0.85% | +0.69% to +1.11% |
| AEGIS-128L, independent repeat | 708.37 ms | 714.62 ms | +0.88% | +0.58% to +1.26% |

Publication is a native microbenchmark; it excludes MoonBit array conversion. Guest timings include the CLI process. The indirect test runs through the WAST Store-binding path, verifies its result, and includes compilation of its tiny module. AEGIS uses separate warm caches, verified in the first run. The AEGIS increase reproduces and remains a limitation of this change. Its CLI path does not use the shared Store callable binding, but context allocation size and native code layout changed; these measurements do not establish the cause. This is not a claim of universal guest throughput improvement.

The first shared-registry implementation regressed indirect calls by 8.03%. Snapshotting the parent pointer/count reduced the regression to 4.76%. Splitting the Store-backed subtype check into a small inline helper removed a nested native call from its successful path; the final result above is a 4.01% improvement. All intermediate samples are retained rather than omitted. The inline change preserves the legacy cache fallback and type-check behavior.

## Validation and evidence

- Strict native MoonBit check with warning 73 enabled and warnings denied.
- 2,608 native tests passed; 63 sanitizer tests passed with instrumentation verification.
- 39 native C stubs passed the strict C check.
- Core WAST: both engines passed 258/258 files and 62,563 assertions each.
- Async 0.3 component WAST: 24/24 files, 153 commands, no skipped commands.
- Module boundary audit passed.

Regression probes cover shared updates, distinct Store identities, local mappings/tags, rebinding, peer teardown, repeated clearing, rejected replacement preserving old data, invalid type indices, and terminal Store closure. Native allocation/free counters balance in the allocation probe. Local validation does not substitute for Windows/Linux CI.

Raw samples, probe source, benchmark scripts, allocation counts, selected assembly, binary/source hashes and validation logs are in [the evidence archive](callable-sharing-2026-09-29.json.gz). The baseline is the pinned commit above; the after source hashes identify the uncommitted source used for measurement. Temporary probe programs are evidence, not a new project audit framework.

## Scope remaining

This removes actual duplicated Store data. It does **not** complete module-shaped VMContext allocation or move exception/GC-root state into activations. Those are explicitly tracked in ISS-602. In particular, 48 bytes in the referenced Wasmtime design describe its fixed prefix, followed by dynamically laid-out instance data and separately owned Store state; it is not a valid total-memory target by itself.

