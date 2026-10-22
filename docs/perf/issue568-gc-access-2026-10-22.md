# Native parse_double GC access costs

This is the first-stage snapshot. The [compiler followup](issue568-local-scalars-2026-10-22.md)
continues the remaining investigation; the original receipt below is preserved.

This addresses two measured sources of [#568](https://github.com/Milky2018/wasmoon/issues/568)
on top of main `55657fb24dfd61937e8d6f1f482df4d23c824631`. It does not establish
Wasmtime parity or close the remaining throughput investigation.

The fixed guest is Core `7547b846d38de3efa5509cb1b74ffb7ed9a4a3d1`,
`internal/strconv/double_quickcheck_test.mbt` test 0, seed 37. The existing
compiled artifact was frozen before the experiments. Host function imports
become same-signature unreachable definitions; the imported tag becomes a
local tag. Function/tag indices, module start and property assertions remain
intact. An exported wrapper checks that the property returns the Ok
discriminant, rather than dropping the result. The short control changes only
the property's iteration count from 20000 to 1000.

Original artifact SHA256:
`16bcf1f9c694573d1fb5f80ed0d44686a130f9f91d501eeeb2697544eca79dc4`.
The two transformed artifact hashes, binary hashes and raw samples are in the
[local receipt](issue568-gc-access-local.json). This is a current-toolchain
control of the pinned Core property; the published 0.17.1 times in the issue
are historical, not the baseline of this comparison.

## Diagnosis and repair

A CPU sample of the original 20000-case run found field access, TLS lookup and
memory copies dominating execution. Collection/allocation samples were much
smaller. Each scalar access crossed several C function boundaries to resolve
the active context, map a stable object identity, inspect its physical layout
and perform a variable-size memcpy. On this macOS compiler, the old activation
getter evaluated two TLS addresses even with an active invocation.

The native repair shares checked accessors between the host API and JIT
helpers. Fixed-size memcpy cases for widths 1/2/4/8/16 permit ordinary scalar
loads/stores while preserving alignment and aliasing safety. Array bounds,
invalid/tombstoned identities, compact/wide layouts, reference write barriers
and environment-controlled verification retain their previous behavior.
The active and fallback activations share one TLS slot; external getter
symbols remain as wrappers. Parking, activation stacking and context ownership
retain the existing protocol.

The compiler also treated every Wasm extension as an unknown effect. The new
`wasm_milkir/optimize` package validates the complete contextual IR first, then
forwards previously executed struct reads and array lengths at O2/O3 before
the generic optimizer. A struct write invalidates that field for all possibly
aliasing object/type identities. Array mutations cannot resize an array or
write a struct field. Calls, allocations, unknown effects, merges and loop
headers discard facts. Packed signedness and carrier types remain distinct.
There is no speculative hoisting or blanket declaration that GC reads are pure.

Availability is bounded to 128 facts, and copy chasing to 64 steps, so large
untrusted functions cannot make this opportunistic analysis copy an unbounded
history. Forgetting a fact leaves an ordinary read. A large-region regression
covers these conservative fallbacks.

CLI compilation, Component compilation, preflight and exploration use the
shared wrapper. Low-level embeddings that own their MilkIR optimization stage
can call it with their `WasmValidationContext`; `NativeCompiler` still accepts
caller-optimized IR and does not silently override an O0 policy. The native C
access improvement also applies to those lower-level callers. Codegen revision
`direct-vcode-12` invalidates older compiled artifacts; the cache rejection
regression explicitly checks revision 11.

## Measurements

Apple M3 Max, macOS ARM64 26.7, Wasmtime 49.0.1, wasm-tools 1.254.0.
Every invocation has a fresh Wasmoon cache; Wasmtime uses
`-C parallel-compilation=n -C cache=n`. Times include cold compilation and
loading. Verification diagnostics are disabled only for the performance runs;
correctness gates enable them. All engine outputs were exactly `1`.

| Control | Baseline wall | Final wall | Wasmtime wall | Samples per engine |
| --- | ---: | ---: | ---: | ---: |
| 1000 cases | 3.706 s | 2.100 s | 0.372 s | 3, median |
| 20000 cases | 63.920 s | 29.561 s | 2.386 s | 1, final confirmation |

Before the final analysis-work bounds, three complete cold runs had medians
64.218 s / 30.099 s / 2.364 s respectively. The bounded final pass produced a
byte-identical 1000-case guest artifact, and its complete final confirmation
agrees with that approximately 2.1x improvement. The final full-case user CPU
times were 63.640 s / 29.466 s / 2.375 s. Raw measurements remain separated by
stage in the receipt rather than relabeled as the same build.

The remaining full-case ratio is about 12.4x, and must not be described as
resolved engine parity. A new sample still places most leaf samples in struct
access helpers, followed by root copies and TLS. Sampling does not distinguish
instruction-cache, data-cache or dependency-chain costs; no hardware-counter
attribution is claimed. Further work should investigate safe address/layout
reuse across accesses with explicit safepoint invalidation.

An isolated direct-JIT-load prototype, combined with the other changes,
completed the full case in 27.379 s. Its 1000-case compilation phase grew from
0.472 s to 0.894 s, while invocation fell from 1.410 s to 1.258 s. It duplicates
the native layout contract and has no cross-platform acceptance. It is not
part of this patch. Profiling runs are not included in the timing table.

Reproduce with fresh native binaries from the baseline and changed sources:

```sh
python3 scripts/benchmark_parse_double_gc.py \
  --artifact /path/to/core/_build/wasm-gc/debug/test/internal/strconv/strconv.blackbox_test.wasm \
  --wasmoon /path/to/fresh/wasmoon \
  --baseline /path/to/baseline/wasmoon \
  --count 20000 --samples 3
```

The script validates the transformed guest, checks every result, alternates
engine order, records wall/user CPU ratios and removes its temporary fixtures
and caches on exit. Its `expected_core_revision` is an input expectation;
artifact provenance must be checked in the caller's Core checkout.

## Validation scope

The optimization regression failed before implementation with two remaining
reads instead of one. Public tests cover aliased writes, packed truncation,
array mutation, calls, allocations, merges, loops, reference carriers, O0/O1,
large regions, malformed contextual IR before mutation, actual O0/O2/O3
JIT/interpreter parity, null and bounds traps. In particular, a packed write
followed by an illegal plain read must be rejected before forwarding can erase
the malformed instruction.

Final native 2974/2974 passes with `VCODE_REGALLOC_VALIDATION=1`,
`WASMOON_GC_VERIFY=1` and `WASMOON_GC_ASSERT_BARRIER=1`; wasm passes 1402/1402.
Strict checks on both targets, info/fmt, module boundaries, generated MSVC
bridges and 178 Python tests (54 existing platform skips) pass.
Fresh isolated macOS ASan/UBSan passes 269/269 and both ASan positive controls.
Those sources are explicitly dirty based on `55657fb2`; macOS LSan is
unavailable. Native ARM execution is not x64 execution. Linux/Windows CI and
Linux leak detection remain pending. The receipt records corpus and source
verification separately. All owned source/build/log/cache workspaces are
removed after verification; only this compact evidence is retained.
