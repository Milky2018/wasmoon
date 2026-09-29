# MoonBit-owned GC type metadata

Date: 2026-09-29. Tracking: ISS-607, part of ISS-602.
Baseline: `577dc23e3879ed0fc18b02366719c10275ccbdcb`.

## Ownership and behavior

Module GC type encoding remains in MoonBit as a pure builder. Setup creates typed FixedArrays for type records, canonical indices and function type indices, then binds all three through one JITContext method owned by jit_ffi. The native context retains those arrays with RC and reads their payloads directly. A regression probe checks payload pointer identity as well as behavior after the original MoonBit owners leave scope.

All new references are retained before any old references are released, including aliasing between canonical/function arrays and rebinding the same arrays. Clear and context finalization release the same reference contract. The high-level Array-taking setup API still snapshots caller inputs. The lower-level FixedArray binding shares storage and explicitly forbids mutation while bound; setup remains serialized with guest execution.

The old implementation skipped canonical publication when the input was empty, leaving the previous map active. A regression test first installs shared canonical identities, then sets up with an empty mapping and verifies that index-based subtype behavior is restored. The pinned baseline fails the second assertion; the new implementation passes. Caller-array mutation is checked separately in the same test.

Legacy raw-pointer C setters retain copy semantics: they create MoonBit-managed array copies, never apply RC operations to raw caller memory, and replace their slots only after making the new copy. Raw and typed bindings can therefore be mixed safely. Allocation uses the MoonBit allocator; there is no separate recoverable native-copy malloc failure. Existing raw-pointer exports remain available for valid inputs.

## Storage and ABI

The native context remains 352 bytes; no native struct field, generated offset or artifact version changes. Native subtype query code is unchanged. For three distinct nonempty arrays, persistent payload storage is the same as before, with three retained MoonBit array headers (24 bytes on this toolchain) instead of headerless malloc buffers. Empty arrays are represented as NULL in the native view and are not retained.

The new MoonBit binding performs no C buffer allocation or memcpy. In the former path, each nonempty table was copied from its temporary MoonBit array into a native allocation. Eliminating those copies does **not** prove that total peak memory always falls: the batched binding prepares all new arrays before releasing all old arrays. Replacement peak depends on table sizes and input lifetimes. No whole-setup peak/RSS or dedicated setup-throughput measurement is claimed here.

Function-address snapshots and safepoint descriptors remain separately owned native storage. This change does not complete module-shaped context layout, shared module metadata, or invocation-control migration.

## End-to-end measurements

Local macOS arm64, MoonBit 0.1.20260920 / moonc v0.10.14+7d59c7ec9. Each workload has 31 retained paired samples after warmup with alternating order. No build/test workload overlaps retained measurements. CLI wall times include startup and WAST compilation. AEGIS samples verify warm-cache hits. The fixtures are the same as the preceding activation report: 10 million indirect calls, one million struct allocations, one million throws/catches, and the existing AEGIS example.

| Workload | Before | After | Median paired change [95% bootstrap interval] |
|---|---:|---:|---:|
| indirect | 292.100 ms | 281.371 ms | -3.56% [-4.39%, -2.52%] |
| gc | 53.828 ms | 52.820 ms | -0.86% [-2.35%, +0.98%] |
| exceptions | 127.126 ms | 126.587 ms | +1.47% [-1.40%, +2.99%] |
| aegis | 852.634 ms | 853.766 ms | +0.13% [-0.12%, +0.57%] |

These are broad end-to-end regression measurements, not a benchmark of metadata setup alone or proof of a particular cache/allocator cause. Small timing differences should not be generalized into a runtime speedup claim.

## Validation

- Baseline stale-canonical regression: 1 failed test at the expected second assertion.
- 2,615 native tests passed, including two new regressions.
- 69 ASan/UBSan tests passed with instrumentation controls.
- Strict MoonBit check with warning 73 enabled and warnings denied.
- 38 C stubs compiled with warnings denied; module-boundary and JIT lifetime checks passed.
- Core WAST: 258 files and 62,563 assertions passed on each engine.
- Async component WAST: 24 files, 153 commands, no skips.
- Ownership coverage: identical payload pointers, alias-safe rebinding, owner release, empty replacement, repeated clear, independent contexts, and legacy C copy semantics mixed with typed bindings.

Cross-platform CI for the new commit is tracked separately. Raw samples, fixtures, probe sources, validation logs and source/binary hashes are retained in [the evidence archive](gc-metadata-2026-09-29.json.gz).
