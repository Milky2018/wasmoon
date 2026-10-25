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


## New #568/#583 controls: frozen toolchain recheck

An installed runner changed during the long session: the initial recorded
SHA256 was `683cfa35312c832f0a59b66ad2b46033cfd8d0936e16e65bc32a3403d65040e4`,
whereas the later October23 installation was
`f0b2caf575622a8134507779e17256e90a29b9632e93ed8a91bd77b3d6876915`.
The unpinned final-poll comparisons and interrupted library round are not
accepted attribution. The results below supersede those provisional numbers.

All five source stages were freshly rebuilt against one private frozen SDK:
Moon/moonrun 0.1.20261023, moonc 0.10.17+d971670cd, including the same standard-library
bundles and native headers. The global installation was not changed. Each stage
has only the identical API-timer harness as a source modification. The downstream
embedding remains ed848ac5, O2, cancellation=true, cooperation=true, quantum 1024.
The current reference is official **October23 moonrun**, not Wasmtime or the
October21 runner reported by the issue. No source/guest assertion is weakened.

Each table contains five fresh-process samples per stage with cyclic order to
balance positions. One small host-image preparation run precedes recording;
every recorded process compiles fresh without an artifact cache. Builds and
profilers stop before timing. RSS is decimal MB. Raw logs stay temporary.

### Compiler-only public API (#583)

Exact input: 4,938,531 bytes, SHA256
`00002138ac7db01edc9217916b8c7b3c96a8e093f47f765faa465ac3eca792a6`.
The O2 API includes parsing, validation and eager compilation, excludes input
reading and encoding, and creates no Store, links no imports and runs no guest.
Cancellation remains enabled; the disabled control is reported separately.

| Source stage | Enabled API | Peak RSS |
| --- | ---: | ---: |
| 0.18.0 release (21c702b5) | 10.590 s | 1531.1 MB |
| Before resumed changes (7b40e8ca) | 8.957 s | 718.4 MB |
| ABI block cursor faea6beb | 7.130 s | 717.0 MB |
| Prepared metadata b6e1cb10 | 7.069 s | 717.1 MB |
| Poll-preserving inlining cc23d6f2 | 6.788 s | 658.3 MB |

The ABI change improves enabled compilation by 20.4%, with unchanged memory. The
plain control improves 7.692 -> 6.016 s (21.8%); final plain compilation at 5.983 s
is effectively flat against that stage. Complete ABI-change artifacts are
byte-identical in both modes. Final plain artifacts are unchanged after
revision 25/26 normalization. The later poll change improves enabled compilation
another 4.0% versus its immediate prepared-metadata predecessor and reduces
compiler RSS by 8.2%. Whole-PR release/final improvement is 35.9% time and 57.0% RSS;
that total includes the earlier changes and is not attributed to the new emitter.

Both emitters now borrow one read-only block snapshot and its known local
position for input/result/output ABI groups. The public snapshot API, parallel
moves, metadata offsets and long-branch fallback are unchanged. A diagnostic on
the original largest initializer records 17,460 snapshots, 350,542,399 copied
handles and 173,302,982 position comparisons per emission attempt, repeated on
fallback. CPU samples directly show copying/reference-release work. The
regression exercises 32 mixed I64/F64/V128 transfers after a CFG join at O0/O2,
both branch arms, plus production cross-compilation for both native targets.

### Same-instance repeated work (#568)

The archived zero/one/ten-call inputs keep their original SHA256 values and
all 1,000-case checks. Every probe must return one; ten calls perform 10,000 checks
after one startup. The stages below use the exact same binaries/SDK as above.

| Stage | Zero calls | One call | Ten calls | Ten-call RSS |
| --- | ---: | ---: | ---: | ---: |
| Official October23 moonrun | 0.010 s | 0.057 s | 0.408 s | 26.2 MB |
| Released Wasmoon | 1.133 s | 2.060 s | 10.398 s | 307.4 MB |
| ABI-emitter stage | 1.027 s | 1.940 s | 10.121 s | 266.3 MB |
| Prepared metadata | 1.025 s | 1.408 s | 4.852 s | 266.8 MB |
| Final poll-preserving stage | 0.932 s | 1.297 s | 4.534 s | 261.3 MB |

Sampling identifies repeated metadata copying/release on cooperative resume.
The retained `PreparedGCEnvironment` freezes type/canonical/function/address
payloads once, bound to their native owner. Every entry/resume still checks the
live instance/module/owner and rebinds metadata plus the **current** heap. Roots,
scopes, callbacks, quotas, rollback and scheduling remain dynamic. Close releases
the snapshot. Legacy setup stays fresh; low-level function-table changes require
explicit preparation. The discarded skip-setup diagnostic could not restore an
intervening binding. Preparation improves ten-call wall by 52.1%; peak RSS is flat.

Eager entry-poll expansion also made every cancellable leaf multi-block and
therefore ineligible for leaf inlining. `SafepointPoll` now stays effectful in
Wasm MilkIR until native lowering. Inlining clones every poll, even for unused
results, and charges eight units against existing budgets for its seven late
CFG blocks. The slow call keeps precise roots and the conservative call contract;
signed offsets and unknown-provider runtime calls are preserved. Codegen revision 26 rejects
stale caches. The enabled serialized artifact grows39.88 -> 42.34 MB (6.2%);
that includes metadata, not just machine code. The cloner avoids duplicate
decoding and general array mapping for its zero/one-result contract. This adds
6.5% ten-call improvement. Disabling polls
is not an accepted optimization or an additive speedup budget: preserved polls
still end checked-reference/physical-borrow lifetimes.

Whole-PR ten-call wall improves 56.4% against release, but remains 11.1x the new
official reference. `(T10-T1)/9` is approximately 0.360 versus0.039 s (9.2x).
These are process/incremental estimates including GC, polling, switching, tiering
and startup, not isolated generated-code timers. Startup and GC/root/access
costs remain open; #568 is not closed.

### Validation and broader inputs

Native 3192 passes ordinarily and with register/GC/barrier verification, wasm 1483
and strict checks on both targets pass. Public tests compare callback counts,
exact fuel outcomes, callback cancellation/reuse, quantum-one yields, GC during
callbacks/parked work and resumed array reads between O0/O2. Compiler tests retain
unused-result polls and precise metadata on both targets. Prepared environments
have public owner/rebinding tests and private payload-reuse invariants.
Fresh isolated Mac ASan/UBSan 373, the event loop and both controls pass on the
dirty a4021683 tree with the exact final functional sources/tests; local LSan is
unavailable. Clean source/platform receipts are tracked in PR582, independently
of these local timings.

The earlier b6e1cb10 library screen passed 36/36 runner/suite/round combinations
and the 70-workload cold screen had zero engine failures. Those are historical
stages, not current-head acceptance. The frozen-SDK final library runs retain
all original Core/async/SQLite counts, cfgs, panics, snapshots, FD checks and four
concurrent executables; guests are prepared outside measurement and their hashes
are checked. Updated library/corpus results belong in PR582. Wasmtime corpus
controls retain `-C parallel-compilation=n`. No raw report or receipt-only commit
is required.
