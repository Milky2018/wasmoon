# MoonBit-owned safepoint payloads and function-address snapshots

Date: 2026-09-29. Tracking: ISS-608, part of ISS-602.
Baseline: `d1bab5a1fc6de663fd83c2420b444278d103825a`.

## Ownership boundary

Safepoint setup now binds its existing Bytes and FixedArray[Int] directly through JITContext. C retains those arrays and exposes their payloads in stable native descriptors. Descriptor addresses must remain stable because GC frames reference them. The descriptor array remains a native allocation; payload replacement and context finalization use MoonBit RC. Bindings are setup operations outside guest execution, and callers must not mutate retained offset arrays.

The legacy function-address snapshot is now a FixedArray[Int64]. Converting a raw native pointer table still requires one copy in C, where pointer conversion belongs. Binding an existing typed snapshot retains it directly. The snapshot contains addresses, not ownership of executable code; existing code-object owners remain necessary. Native tagged-funcref lookups compare integer addresses without aliasing the Int64 payload as a pointer array.

Incoming references are retained before releasing replaced references. Legacy raw C setters copy their inputs into managed arrays; they never apply RC to caller-owned raw buffers. Managed and raw bindings share one release contract. Managed payload allocation follows MoonBit allocator behavior, replacing the old recoverable malloc-copy failure path; native descriptor allocation can still return failure.

## Storage and ABI

A local compiled layout probe reports a 352-byte context, 128-byte generated prefix, 32-byte safepoint descriptor and 8-byte MoonBit object header. No generated offset or artifact revision changes. Descriptors still occupy 32 bytes per context function when allocated.

For distinct dynamically allocated nonempty safepoint payloads, the retained Bytes and offsets add two 8-byte object headers and one Bytes terminator byte relative to old headerless persistent C copies, before allocator rounding. A nonempty function-address array adds an 8-byte header on this 64-bit target. Empty payloads are represented as NULL and are not retained. Shared arrays can share payload storage across bindings; no whole-module sharing scheme is introduced here.

The typed safepoint binding eliminates the second payload allocation and memcpy. This is an ownership simplification, not evidence that persistent memory or peak RSS always decreases. Raw compatibility setters and raw function-pointer conversion still copy. No dedicated setup-throughput or peak-memory measurement is claimed.

Module-shaped context layout, shared module metadata, invocation-control configuration and native resources remain separate work under ISS-602.

## End-to-end measurements

Local macOS arm64. Each workload has 31 retained paired samples after warmup, with alternating execution order and no overlapping build/test workload. CLI wall time includes process startup and WAST compilation. AEGIS samples verify warm-cache hits. Fixtures match the preceding reports: 10 million indirect calls, one million struct allocations, one million throws/catches, and the existing AEGIS example.

| Workload | Before | After | Median paired change [95% bootstrap interval] |
|---|---:|---:|---:|
| indirect | 225.934 ms | 222.858 ms | -0.31% [-2.74%, +1.37%] |
| gc | 44.900 ms | 44.515 ms | -0.51% [-0.78%, -0.08%] |
| exceptions | 103.728 ms | 104.721 ms | +1.26% [+0.35%, +2.98%] |
| aegis | 710.661 ms | 707.988 ms | -0.20% [-0.77%, +0.02%] |

These broad regression measurements do not isolate metadata setup or establish a cache/allocator cause. Timing differences must not be generalized into a runtime speedup claim. In this run the exception workload is 1.26% slower by median paired change (interval +0.35% to +2.98%); this small observed regression is retained in the report rather than described as unchanged. The measurements do not isolate its cause.

## Validation

- 2,616 native tests passed.
- 70 ASan/UBSan tests passed with instrumentation controls.
- Strict MoonBit check with warning 73 enabled and warnings denied.
- 38 native C stubs compiled with warnings denied; existing module-boundary and lifetime checks passed.
- Core WAST: 258 files and 62,563 assertions on each engine.
- Async component WAST: 24 files and 153 commands, no skips.
- New regression verifies payload pointer identity, owner release, same-array rebinding, invalid index preservation, replacement, repeated clearing, context isolation and mixed legacy raw bindings.
- Existing raw safepoint regression verifies descriptor address stability, peer-slot isolation and copied inputs.

Cross-platform CI for the new commit is tracked separately. Raw timings, fixtures, probes, validation logs and hashes are retained in [the evidence archive](safepoint-metadata-2026-09-29.json.gz).
