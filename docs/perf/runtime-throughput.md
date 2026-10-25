# Typed allocation throughput

Local macOS ARM64 measurements against main `21c702b5` (0.18.0).
Tracking: [ISS-679](../../issues/ISS-679.md). These are release binaries built
from the stated base and an explicitly dirty implementation tree, not CI
acceptance or a general engine ranking. The allocation changes do not alter
object layout, the root protocol or public APIs. A separate
[integer compiler follow-up](wide-multiply.md) recognizes wide multiplication.
The later pressure follow-up changes collection admission timing, not the
collector implementation.
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

## Prepared typed allocation follow-up

A 3-second CPU sample of 300 million four-element i32 allocations on e4ff2f70
put approximately 86% of main-thread samples in the allocation chain, including
about 12% in collection; array projection accounted for another 9%. The sample
is attribution, not a timing run. Optimized V8 machine code still allocates
these arrays through its bump-pointer path, but forwards some subsequent
fresh-array reads. Allocation cost alone therefore does not explain the gap.

Typed allocation now consumes the existing prepared identity/live-list window
when debug controls are known disabled, no quotas are bound, and payload,
identity and collection capacity suffice. It increments the same attempt
counter and uses one shared publication primitive. Otherwise the original
fault-injection, quota admission, capacity growth and verifier path runs.
Payloads are initialized before publication; no new root, layout, collector
policy or public API is introduced. Collection and rollback already invalidate
prepared capacity. A public regression retains more than two identity pages,
rolls back a newer page, allocates again, collects and checks every payload.

Three alternating serial samples of 100 million allocations per case
(`--samples 3 --scale 1000` with the three small-array cases), invocation seconds:

| Elements | e4ff2f70 | Prepared | V8 | Reduction |
| --- | ---: | ---: | ---: | ---: |
| 4 | 3.066 | 2.301 | 0.385 | 24.9% |
| 1 | 3.284 | 2.531 | 0.342 | 23.0% |
| 17 | 3.899 | 2.980 | 1.750 | 23.6% |

The baseline is independently built from e4ff2f70 in a temporary checkout;
binary SHA256 prefixes are e88a6c2ba269 / 51ca4ce12597. All controls return 1.
Five samples of the full parse_double property give 1.899 / 1.878 seconds
invocation and 0.818 / 0.823 seconds compilation: only a small real-workload
change, not a solution to its remaining execution gap. The seven-case shorter
screen leaves large-array and graph throughput essentially unchanged. No RSS
improvement is claimed: long small-array controls still reach 156–175 MB.

Follow-up validation: full native3103 with register-allocation, GC and barrier
verification; ordinary sanitizer package214; wasm1462; Core interpreter/JIT
each258/62563; strict checks on both targets; 44 C stubs and module/bridge audits.
Fresh isolated local ASan/UBSan314, event loop and both ASan positive controls
pass on the dirty e4ff2f70-based tree. macOS does not provide LSan acceptance;
this follow-up requires its own Linux/Windows CI after commit.

## Collect before unnecessary growth

The next allocation could cross the collection threshold before the existing
used-size check noticed pressure. Two arrays each half the physical capacity
plus 16 bytes reproduced a 1 MiB to 2 MiB growth with no collection, even with
the first array dead. The retained-live control already returned the right
values and legitimately needed growth.

The common collecting allocator now estimates a conservative slot-size bound;
only near physical exhaustion does it resolve the exact typed size. If the
allocation would need growth and cross the collection threshold, the existing
precise-root collection runs first. Surviving objects can still require normal
growth. Impossible allocations, explicit-GC low-level heaps, quotas and failure
policy retain their existing paths. Typed sizing is shared with allocation.
No lower threshold or new configuration is introduced.

Five serial samples against f866185a (binary prefixes 51ca4ce12597 /
b74e4bee5ef1) reduce the 17-element control from 41.873 to 31.069 ms invocation
and peak RSS from 155.96 to 88.82 MB. Other controls have no clear improvement;
this is a boundary-specific result, not a general RSS claim. Full native3105
passes in ordinary and all-three-verifiers modes. Fresh isolated macOS
ASan/UBSan316, event loop and both positive controls pass on the dirty
f866185a-based tree; Linux LSan still requires CI for this new change.
Core258/62563 and Component59/1385 also pass in each engine with verification
enabled; wasm1462, strict checks, C44 and boundary/bridge audits pass.


## Distributed Core compiler: block-local ABI emission

The new #583 control uses the 4,938,531-byte distributed Core builtin GC module,
SHA256 `00002138ac7db01edc9217916b8c7b3c96a8e093f47f765faa465ac3eca792a6`.
The public compile_module API parses, validates and eagerly compiles at O2;
there is no Store, import linking or guest execution. Cancellation remains
**enabled** in the acceptance configuration. Tracking: [ISS-704](../../issues/ISS-704.md).

Fresh 0.18.0 controls reproduce 10.617 seconds API time and 1,530.6 MB peak RSS
(three serial samples). PR582 at 7b40e8ca already reduces memory substantially;
those release observations must not be attributed to the following single fix.

Sampling the current compiler's final initializer emission identified repeated
block snapshots and linear instruction-position searches. A diagnostic counter
on the unmodified algorithm records 17,460 snapshots, 350,542,399 copied handles
and 173,302,982 position comparisons in that function's emission attempt. Its
long-branch fallback repeats the work. The largest initializer has 73,107 IR
instructions after optimization. CPU samples directly attribute the time to
Array.copy, reference blits and reference-count release inside ABI emission.

Both target emitters now borrow the emission loop's one block snapshot and
known block-local position. Input/result/output transfer grouping and parallel
moves are unchanged. The public Function.block_body snapshot contract is also
unchanged. No global cache, public API, artifact version or codegen revision
changes. The private ArrayView parameter prevents helper-side mutation.

Five alternating fresh-process pairs on macOS ARM64, before 7b40e8ca versus its
dirty tree with only this functional emitter change, without concurrent builds
or profiling (decimal MB; API timing excludes input reading and encoding):

| O2 mode | API before | API after | Change | RSS before / after |
| --- | ---: | ---: | ---: | ---: |
| cancellation enabled | 8.807 s | 7.136 s | -19.0% | 718.3 / 718.3 MB |
| cancellation disabled control | 7.742 s | 6.041 s | -22.0% | 646.9 / 646.9 MB |

Separately encoded complete artifacts are byte-identical before/after in both
modes (SHA256 prefixes `1fb5e1dce158` / `523a2fbe6952`, respectively). This is a
compiler-work reduction, not an RSS or guest-throughput improvement. Public
regressions compile repeated mixed integer/FP/vector transfer groups in a
non-entry block on both targets; actual JIT/interpreter comparisons exercise
32 repeated mixed register/stack/result-area transfers at O0 and O2. These
semantic regressions pass before and after; deterministic diagnostic work counts
and repeated original-input timings provide the performance feedback loop.
No timing threshold or test-only production counter is added. Local ARM64
execution does not establish actual x64 execution or fresh cross-platform CI.

## Cooperative execution: immutable GC environment preparation

The new #568 controls use the archived downstream embedding at ed848ac5,
unchanged except for resolving Wasmoon dependencies to the compared local
workspaces. Compilation stays O2 with cancellation=true, cooperation=true and
the default quantum of 1024. The exact zero/one/ten-call Wasm inputs retain every
probe assertion. The new reference is installed official moonrun 0.1.20261021,
not the older standalone Wasmtime control. Tracking: [ISS-705](../../issues/ISS-705.md).

After startup, approximately 59% of main-thread samples are in repeated GC
preparation, metadata array copying and temporary releases on cooperative resume.
A separate single-variable diagnostic that avoids repeated preparation reduces
ten-call wall time 10.145 -> 4.849 s without changing scheduling or guest code.
That diagnostic does not satisfy intervening-binding semantics and is discarded.

The retained design freezes module type/canonical/function maps and native
function addresses in a context-bound `PreparedGCEnvironment`. High-level module
addresses and `JITModuleContext`'s read-only maps are immutable after installation,
so preparation happens once. Each entry/resume still checks the live instance,
module and native owner, then rebinds the same immutable arrays and **current**
heap. Dynamic roots, execution scopes, callbacks, cancellation, scheduling,
quotas and rollback remain live state and are never captured by this snapshot.
Close releases the cached environment. Legacy dynamic setup keeps its existing
fresh-snapshot semantics. Native users who change their function table must
explicitly prepare a new environment; the prepared addresses do not own code.

Five alternating ordinary fresh-process pairs on macOS ARM64, immediately before
versus the c873e8b0-based dirty functional tree, after all builds/profiles stop:

| Calls | Whole process before | After | Peak RSS before / after |
| --- | ---: | ---: | ---: |
| 0 | 1.040 s | 1.049 s | 65.1 / 65.1 MB |
| 1 | 1.946 s | 1.412 s | 142.9 / 142.9 MB |
| 10 | 10.124 s | 4.888 s | 266.9 / 266.6 MB |

The ten-call reduction is 51.7%. `(T10-T1)/9` changes approximately 0.909 -> 0.386 s
per extra probe. This includes GC, polling, switching and process-state effects;
it is not an isolated in-guest timer. The same archived official runner's earlier
three-sample medians are 0.058 s for one call and 0.415 s for ten: the current ten
call path remains approximately 11.8x slower end-to-end, and its rough incremental
estimate remains approximately 9.7x slower. No remaining-gap closure is claimed.

Prepared payloads add stable O(module metadata) retained storage, without a
measured peak-RSS improvement. Regressions protect input snapshots, alias-safe
reuse of the exact payload arrays, clearing/rebinding, explicit address refresh,
foreign-context rejection, and cooperative resume after an unrelated heap/map
was installed. Full native 3187 passes ordinarily and with all three verification
flags, wasm 1481 and both strict targets pass. Fresh isolated macOS ASan/UBSan 370,
the event loop and both positive controls pass on the dirty c873e8b0 tree. This
does not establish Linux LSan or actual x64/platform acceptance. Full distributed
library and cross-platform results are tracked in PR582; raw logs stay temporary.

The final public regression places the repeated mixed ABI transfers after a CFG
join, exercising both arms. A deliberate global-instruction-index substitution
fails with an out-of-range block view; the correct block cursor passes. The
foreign-context prepared-environment test now uses only the public API. Native
3187 (ordinary and all verification flags), wasm 1481 and strict checks pass;
fresh isolated macOS ASan/UBSan now executes 371 tests plus both positive
controls. This last run uses b6e1cb10 with test-only working changes, not a clean
platform acceptance receipt.

### Distributed library and corpus controls

Three rounds retain the original four concurrent test executables, cfgs,
expected panics and snapshots. All 36 runner/suite/round combinations pass, with
unchanged Wasm hashes and counts: Core wasm 7950, Core GC 7971, async 586 and
SQLite 46. Medians include process startup, JIT, host work and waits; these are
whole-PR comparisons against release 0.18.0, not isolated guest execution or
attribution to one change.

| Suite | Official moonrun | Released Wasmoon | Current functional tree |
| --- | ---: | ---: | ---: |
| Core wasm | 6.061 s | 41.461 s | 29.349 s |
| Core GC | 3.147 s | 78.727 s | 46.887 s |
| async | 15.689 s | 23.135 s | 22.764 s |
| SQLite | 0.579 s | 1.375 s | 1.340 s |

A fresh serial cold screen of all 70 algorithm workloads completes with zero
engine failures. Wasmtime 49.0.1 has parallel compilation disabled; Wasmoon
reports a fresh compile for every workload. Geometric mean ratios are 1.029 for
69 positive finite guest values and 1.369 for all 70 cold process wall times.
Twenty-four cases exceed the runner's performance-warning thresholds. These
single-screen aggregates are essentially unchanged from the earlier screen;
no corpus-wide improvement is claimed from the new cooperative metadata fix.

### Remaining cancellation/inlining interaction

Single-variable controls retain all guest checks. Three fresh rounds give
ten-call medians of 4.939 s with normal cancellation/cooperation, 4.522 s with
only cooperation disabled, and 1.694 s with both disabled. Cancellation also
changes compiler eligibility: its eagerly expanded entry CFG prevents the
single-block leaf inliner from running. A separate three-pair control with both
features disabled increases ten-call time from 1.638 to 3.967 s when only leaf
inlining is disabled. Therefore the cancellation gap cannot be attributed to
poll instruction cost alone. These diagnostic switches are not production
settings; preserving every entry/loop poll and its roots is required for any
follow-up inlining change.
