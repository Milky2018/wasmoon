# Typed initialization throughput

Local macOS ARM64 measurements against main `21c702b5` (0.18.0).
Tracking: [ISS-679](../../issues/ISS-679.md). These are release binaries built
from the stated base and an explicitly dirty implementation tree, not CI
acceptance or a general engine ranking. No compiler, GC policy, object layout,
root protocol or public API changes are retained.
Measured baseline/candidate binary SHA256 prefixes are `3185b22dca61` /
`0c522f45ed12`; the runners record complete binary and guest hashes.

## Retained changes

1. Typed default-zero arrays and structs reuse the allocation's existing zeroing
   instead of rewriting every field/element. Both vector words participate in
   deciding whether an initializer is zero.
2. Arrays of at least one 16-byte block whose elements will all be written
   initialize metadata and alignment padding separately, avoiding a full zero
   pass before the real fill. The
   complete body is initialized before publishing the object identity. Struct
   padding and sub-vector arrays retain the original whole-object zeroing.
3. Repeated initialization shares the existing bulk-fill path. Byte-repeated
   values use `memset`; other widths use a repeated 16-byte pattern, fixed-size
   `memcpy` blocks and an exact tail. Sub-vector fills retain scalar copies;
   zero-length operations return immediately. This avoids unaligned typed accesses,
   platform intrinsics and per-element variable-size copies. Reference admission
   and bulk-write barriers stay with their existing callers.

The scalar-width loop initially used constant-sized `memcpy` per element.
Clang's optimization remarks and object disassembly showed scalar stores, not
automatic vectorization. The block form emits 16-byte loads/stores. A separate
five-sample control reduced nonzero i32 invocation from 115.463 to 46.162 ms;
it did not improve the already full-width v128 loop. Avoiding redundant zeroing
accounts for that workload's cumulative gain below.

## Measurements

`scripts/benchmark_gc_workloads.py --samples 5 --scale 10` generates and validates
the same asserted guest for every engine. Arrays cumulatively allocate about
1.6 GB; the graph control keeps a 32768-node chain, mutates a reference ring,
churns arrays across collections, then verifies the live graph. Every probe
returned 1. Samples alternate engine order and run serially, without concurrent
builds or profiling. Sources, samples and cold caches are automatically removed.

Wasmtime 49.0.1 explicitly uses `-C collector=copying -C parallel-compilation=n
-C cache=n`. V8 14.1.146.11-node.14 uses `--no-liftoff
--no-wasm-lazy-compilation --wasm-num-compilation-tasks=1`: optimized eager serial
compilation, not a claim that GC has no worker threads.

Median invocation time, milliseconds (one asserted export call):

| Guest | Main | Change | V8 | Main / change |
| --- | ---: | ---: | ---: | ---: |
| i32 zero | 311.602 | 33.458 | 28.360 | 9.31x |
| i32 nonzero | 321.801 | 56.790 | 33.507 | 5.67x |
| i32, 4 elements | 35.202 | 31.193 | 4.242 | 1.13x |
| i32, 1 element | 30.467 | 31.280 | 3.480 | 0.97x |
| i32, 17 elements | 55.460 | 51.034 | 18.134 | 1.09x |
| v128 high word | 121.427 | 42.047 | 38.405 | 2.89x |
| survivors and mutation | 314.380 | 41.989 | 27.128 | 7.49x |

Whole-process wall medians, milliseconds; these include compilation and teardown
and must not be substituted for Wasmtime invocation times:

| Guest | Change | Wasmtime | V8 / Node |
| --- | ---: | ---: | ---: |
| i32 zero | 41.785 | 79.170 | 80.543 |
| i32 nonzero | 64.661 | 170.610 | 85.781 |
| i32, 4 elements | 39.396 | 13.458 | 60.915 |
| i32, 1 element | 37.813 | 10.454 | 52.087 |
| i32, 17 elements | 58.419 | 16.635 | 66.396 |
| v128 high word | 48.987 | 89.402 | 88.401 |
| survivors and mutation | 50.733 | 458.279 | 77.111 |

Compilation is unchanged at approximately 0.4–1.7 ms in these tiny guests.
Peak RSS is also unchanged: Wasmoon approximately 76 MB (arrays) / 80 MB
(graph), Wasmtime 14 / 19 MB, V8 / Node 65 / 66 MB. Whole-process RSS includes
different host runtimes; this work does not solve memory footprint or claim a
collector improvement. The short-array controls use one million allocations,
including a partial-block tail. The one-element case is 2.7% slower in this
round; no tiny-object speedup is claimed. It retains the scalar path after an
earlier block-preparation experiment regressed by about 12%. The 17-element
case reaches 156 MB RSS on both Wasmoon builds, versus 14 MB Wasmtime / 52 MB
V8 / Node. Small-object allocation and heap footprint remain clear follow-up
targets, not solved problems.

The real pinned Core parse_double property also retains all 20000 iterations
and returns 1 on each engine. Five samples using
`scripts/benchmark_parse_double_gc.py --v8 --samples 5` give:

| Boundary | Main | Change | V8 | Wasmtime |
| --- | ---: | ---: | ---: | ---: |
| Invoke (ms) | 2007.701 | 1900.167 | 725.885 | not isolated |
| Compile (ms) | 815.503 | 814.056 | 416.122 | not isolated |
| Whole process (ms) | 2901.336 | 2791.726 | 1191.718 | 2384.632 |

Invocation improves 5.4%; compilation is effectively unchanged. The change is
still 2.62x V8 invocation time and 1.17x Wasmtime cold wall time. The Wasmoon
compile timer excludes parse/validation and code installation; V8's
`WebAssembly.Module` timer includes validation/publication. Neither timer is a
Wasmtime compile comparison. Core revision is
`7547b846d38de3efa5509cb1b74ffb7ed9a4a3d1`; the extracted asserted guest SHA256
is `fb7bf21507c21de4ffb79126f94cc0846314bd0b03c33060a533f15afe441db1`.

## Broad screening and rejected work

The main/Wasmtime screen completed all 70 original algorithm pairs with fresh compilation evidence
and no execution failures. This one-pair screen selects investigation targets;
it does not establish an aggregate speedup. Many long linear-memory cases were
already close to Wasmtime; short cases still expose cold compilation overhead.
The sampled crypto modules contained no SIMD shuffles, ruling out that proposed
emitter target for those guests.

An independently tested ARM64 shift/rotate-plus-logic fusion reduced stream's
function 55 from 4076 to 3548 machine-code bytes (160 to 64 standalone rotates,
plus 96 fused operations), but five cold pairs regressed from 5.487 to 5.793 s.
The experiment and its compiler/API/artifact-revision changes were removed.
Smaller code is not sufficient performance evidence. Wasmtime 49.0.1 also emitted
160 standalone rotates in the same function; no claim of a missing universal
optimization follows from the instruction set alone.

After removal, three cold pairs plus a warmup and separate diagnostic captures
on stream, hash, hash3, auth and xchacha20 produced byte-identical artifacts
between main and the retained runtime change. Stream wall medians were
5.492 / 5.495 s; xchacha20 1.649 / 1.650 s. No speedup is claimed for these
unaffected linear-memory controls. Short-case wall measurements remain noisy.

## Validation boundary

Tests cover every scalar width, high-only v128 bits, null/reference initializers,
empty arrays, non-block-sized tails, explicit values and dirty arena reuse after
collection. Existing mixed-layout copies, overlap directions, reference barriers,
quotas and rollback regressions remain enabled. Cross-platform and sanitizer
results must be recorded separately from these local performance samples.

Final local validation: info/fmt and strict native/wasm; native 3102/3102 with
`VCODE_REGALLOC_VALIDATION=1`, `WASMOON_GC_VERIFY=1` and
`WASMOON_GC_ASSERT_BARRIER=1`; wasm 1462/1462; 180 Python tests with 54 existing
platform skips; module boundaries, generated MSVC bridges and 44 strict C stubs.
Fresh isolated ASan/UBSan passes 313/313 tests, the event-loop fixture and both
ASan positive controls. Its sources were explicitly dirty on 21c702b5; local
macOS does not provide Linux LSan or execute x64 instructions.

CLI interpreter and JIT each pass Core 258/62563 with verification enabled;
portable native and actual wasm each pass the same 258/62563. Component passes
59 files / 1385 commands on each engine with zero skips. CLI behaviour, real
archive installation, WASI execution on both engines, packaged native/wasm
embedding and 17 packaged native diagnostic regressions pass. Owned temporary
sources, builds, caches, profiles and reports were removed; no raw receipts are
committed. Linux/Windows execution and leak acceptance remain CI work.
