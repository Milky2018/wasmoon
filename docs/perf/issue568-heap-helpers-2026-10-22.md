# parse_double: explicit heaps and fused GC accesses

This follows the [private scalar repair](issue568-local-scalars-2026-10-22.md)
for [#568](https://github.com/Milky2018/wasmoon/issues/568). Earlier receipts
remain historical. The accepted implementation retains actual object layout
resolution; the faster static-layout candidate described below was rejected.

## Accepted change

Scalar struct and array helpers receive the heap explicitly from the embedding
environment. The environment field is mutable and loaded for each access, so
host callbacks and later heap binding cannot leave a cached heap pointer.
The normal access path no longer finds the active context through TLS or
decodes its module-shaped layout. Trap paths still use activation state.

Array bounds checking and the actual element access share one object-header
resolution. Disassembly of the preceding implementation showed a second sparse
identity-page lookup, payload-offset lookup and length load after the first
bounds check. The new helper carries that checked header and data pointer
through the operation and resolves the actual element layout once.

Existing helper symbols remain wrappers around the same implementation. The
optional explicit heap ABI preserves existing consumers that omit the field.
Windows guest bridges are regenerated. Codegen revision 14 rejects artifacts
compiled against revision 13. No object address survives an operation; there
is no address cache or invalidation protocol to synchronize with moving GC.
Null, bounds, tombstone, reference barrier and verifier behavior remain enabled.

## Why static layout hints were removed

A separate candidate supplied field offsets and widths from the validated
module. It reached a 2.83x wall ratio on the pure property, but failed a later
boundary regression and is **not accepted evidence for the final repair**.

The low-level JIT entry bridge currently accepts raw array identities with
broad reference-variant matching. Passing a compact byte array to an entry
declared with a word-array parameter exposed the difference: the established
dynamic access reads the actual byte element as 7, while the candidate used
word stride and read 0. Its write stride could likewise target the wrong
portion of the object. A module-level type alone does not prove the physical
layout of every raw reference admitted through this boundary.

The final implementation therefore uses the actual immutable descriptor.
The new regression checks both reading 7 and truncating a subsequent write
of 511 to 255. It also passes with GC and barrier verification enabled.
Removing remaining layout queries requires a sound concrete-type proof at
the relevant boundaries; a compiler hint cannot supply that proof by itself.

Fully inlined access prototypes were also rejected: cold 1000-case time rose
to about 1.7 seconds, and their static-layout variants had the same boundary
problem. No prototype emitter, layout-plan query or duplicated layout encoder
remains in production sources.

## Frozen-source comparison

The [receipt](issue568-heap-helpers-local.json) contains raw samples, separate
kernel counters, sampling, intermediate experiments and the rejected candidate.
Measurements use macOS ARM64, Wasmtime 49.0.1 and the unchanged pinned Core
property, seed, import isolation and assertion predicate. Every result is 1.

Each invocation has a fresh Wasmoon cache; Wasmtime uses parallel compilation
disabled and cache disabled. Diagnostic flags are disabled for timing and
enabled for correctness checks. These are three-sample cold CLI medians,
including compilation and startup, with alternating engine order:

| Cases | Preceding repair wall / user CPU | Accepted repair wall / user CPU | Wasmtime wall / user CPU |
| --- | ---: | ---: | ---: |
| 1000 | 1.197 / 1.170 s | 1.120 / 1.096 s | 0.378 / 0.370 s |
| 20000 | 9.545 / 9.489 s | 7.400 / 7.346 s | 2.404 / 2.394 s |

Full-case wall time decreases 22.5%, a 1.29x throughput improvement. The
remaining wall ratio is **3.08x**. The same-run baseline ratio is 3.97x;
the preceding report's independent measurements gave 3.86x.

Separate full-case kernel-counter trials retire 219256245281 instructions
before this change and 163432511201 after it, a 25.5% reduction. Wasmtime
retires 60853898855: the accepted implementation still executes about 2.69x
as many instructions. Peak RSS is essentially unchanged, approximately
352 MB for both Wasmoon variants versus 71 MB for Wasmtime in those trials.
These are individual counter trials, not the timing medians above.

The final active-stack sample still concentrates in checked GC helpers.
TLS lookup is a much smaller leaf. The remaining costs include the helper
calls, sparse-identity resolution and actual descriptor accesses; the evidence
does not attribute the remaining gap to one microarchitectural mechanism.

## Validation and provenance

- Native 2991/2991 with regalloc, GC and barrier verification; wasm 1412/1412.
- Native interpreter, JIT and actual wasm Core: each 258 files and 62563
  assertions, zero failures or unsupported cases.
- Component interpreter and JIT: each 59 files and 1385 commands, zero skips.
- Fresh isolated macOS ASan/UBSan: 273/273, both ASan controls detected,
  system allocator and event-loop control passed. macOS LSan is unavailable.
- Strict native/wasm checks, info/fmt, module boundaries, generated MSVC
  bridges and Python 178 tests with 54 existing platform skips passed.
- Public diagnostic coverage selects the helper contracts on both native
  targets. Runtime execution here covers ARM64, not x64 or Windows.
- Raw-boundary, wide-layout, two-heap, tombstone, inherited-field, packed,
  floating-point, null, bounds, reference-write and post-GC cases are covered.

Sources are an uncommitted tree based on 55657fb2. The 810-file functional
manifest is 5a54694de4a7675491e6a36c74450494269bc4785f9bbbd02c7db91b2812cac5;
the receipt defines its scope. The isolated build copies were compared byte
for byte with that tree. All owned temporary source, build, binary, cache and
profile directories are removed. This is local evidence, not CI acceptance,
publication or a claim that #568 is fully resolved.
