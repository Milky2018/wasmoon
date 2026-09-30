# MoonBit-owned instance segments

Date: 2026-09-29. Tracking: ISS-611, part of ISS-602.
Baseline: `6d447b7da60e410c856fe5a1cc59d9eb79d652ed`.

## Ownership boundary

MoonBit constructs private outer arrays for each context. Immutable data Bytes are retained without copying their payloads. Mutable element input arrays are copied into FixedArrays containing (value, type) pairs. The native binding consumes both outer arrays through explicit owned FFI parameters; context teardown decrefs them. Rebinding prepares the complete new snapshot before releasing old references.

Native memory/table/GC helpers read payload lengths from MoonBit array headers. A dropped segment is represented by an empty payload, eliminating separate size arrays and dropped bits. Guest drop releases the instance's old reference; other contexts and the defining module may still retain the same immutable bytes. Repeated drop is a no-op for an already empty payload. A data drop creates one empty Bytes object when replacing a nonempty payload; an empty element FixedArray uses the runtime's empty array.

Per-instance outer arrays are essential: sharing a mutable outer array would make one instance's drop affect another instance. The public typed setup API constructs private arrays rather than exposing an unsafe shared-array binding. Legacy raw C setters still copy their inputs into managed arrays, so raw buffers are never passed to RC operations. Raw and typed setup use the same destruction contract. As with earlier migrations, payload allocations use the MoonBit allocator rather than a recoverable malloc-copy failure. Typed binding reports failure if the small optional native state allocation fails.

The previous element API silently ignored an incomplete trailing pair. The MoonBit snapshot preserves that behavior. Dropped inputs are published empty without copying unused contents. Bounds checks remain necessary even for zero-length operations, and apply to memory.init, table.init and GC array segment operations.

## Storage and layout

A compiled local macOS ARM64 probe compares the baseline declaration with the current declaration:

| Object | Before | After |
|---|---:|---:|
| Context | 352 bytes | 352 bytes |
| Generated prefix | 128 bytes | 128 bytes |
| Optional segment state | 64 bytes | 16 bytes |

With both segment kinds present, native state plus six parallel metadata arrays becomes native state plus two managed reference arrays: seven structural allocations become three, excluding payloads and input/build temporaries. With no segments, typed setup allocates no native segment state and clears any previous state.

Managed arrays have object headers, and Bytes have a terminator byte. The smaller state and fewer parallel metadata arrays do not alone establish a universal RSS reduction. The data binding's original-payload identity is tested directly. Element payload publication removes the extra C copy. This report does not claim measured peak RSS or total setup allocation counts.

Generated-code offsets and artifact format are unchanged. Module-shaped context layout and the earlier invocation-control timing investigation (ISS-610) remain separate work.

## Validation

- 2,618 native tests and 72 ASan/UBSan tests passed.
- Strict MoonBit checks with warning 73 enabled; 38 C stubs compiled with warnings denied.
- Existing lifetime and module-boundary audits passed.
- Core WAST: 258 files and 62,563 assertions per engine, including dropped/zero-length and GC segment operations.
- Async component WAST: 24 files, 153 commands, no skips.
- New ownership regression verifies original data pointer identity, caller-array mutation isolation, owner release, independent instance state, legacy input copying, dropped raw input replacement, repeated clearing and replacement.

Cross-platform CI for this commit is tracked separately.

## Targeted end-to-end measurements

Local macOS ARM64, JIT enabled. The memory workload performs five million 256-byte memory.init operations; the table workload performs one million 64-element table.init operations. Both then drop the segment and validate zero-length initialization and the destination value. Each has 31 retained paired samples after warmup, with alternating execution order and no overlapping build/test workload. Times include CLI startup and WAST compilation. The baseline executable hash matches the preceding report's tested executable.

| Workload | Before | After | Median paired change [95% bootstrap interval] |
|---|---:|---:|---:|
| memory.init | 54.638 ms | 55.139 ms | +0.73% [-0.92%, +1.90%] |
| table.init | 20.583 ms | 20.246 ms | -2.25% [-3.05%, -0.76%] |

These are targeted end-to-end observations, not isolated setup timing or evidence of general runtime performance. They do not resolve the earlier ISS-610 measurements. Raw timings, fixtures, validation logs, layout probe and source/binary hashes are retained in [the evidence archive](segment-ownership-2026-09-29.json.gz).
