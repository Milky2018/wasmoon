# Stable native GC heap experiment

The local `milky/gc-direct-references` experiment starts from `0ca9b5a6`.
Set `WASMOON_EXPERIMENT_STABLE_HEAP=1` to use reserved address space,
commit-on-growth, and coalesced free extents. Live objects keep their address
through growth and collection. Object identities, reference words, generated
accesses, and root publication still use the original contracts. This isolates
the cost of keeping payload addresses stable with the original reference format.

The first variant reconstructed holes by walking the payload and decommitted
unused tail pages. The second variant, present in this checkout, sorts and
merges only dead and free spans and retains the committed tail during
allocation-triggered collections. Byte quota accounting excludes reusable
holes. An independent verifier matches live identity offsets to the physical
partition and checks the free links.

## Paired measurements

macOS ARM64, release builds with MoonBit SDK 20261104. Each variant ran the clean
baseline, its own compacting mode, and its stable mode in fresh processes, with
alternating order, separate caches, one control round and five retained rounds
per input. All 108 processes returned the expected value. The compacting arm of
each candidate is the matched control. Invocation metrics start after code
installation. Peak RSS is for the whole process in decimal MB.

| Input | First compact / stable invoke | Second compact / stable invoke | Second compact / stable RSS |
| --- | ---: | ---: | ---: |
| Original parse_double, 20,000 cases | 1.421 / 2.257 s | 1.420 / 3.224 s | 265.7 / 226.1 MB |
| Retained graph, 2,097,152 nodes and 100,000 churn iterations | 103.6 / 215.5 ms | 103.3 / 106.6 ms | 291.9 / 202.0 MB |
| Interleaved lifetimes | 18.7 / 34.3 ms | 18.7 / 38.4 ms | 78.5 / 143.5 MB |

The first input is the pinned property from `benchmark_parse_double_gc.py`,
probe SHA-256 `fb7bf21507c21de4ffb79126f94cc0846314bd0b03c33060a533f15afe441db1`.
The retained graph uses `graph_workload` from `benchmark_gc_workloads.py`.
The interleaved input allocates 120,000 arrays of length `1 + (i & 4095)` and
links a retained node every 64 iterations. It asserts the final element of every
new array and the count and checksum of retained nodes.

A separate execution sample used six calls of the same checked property. The
first stable variant spent 184 of 3,073 main-thread leaf samples in storage
reservation and 53 in free-span rebuilding. The second had 97 of 3,058 in
storage reservation and 104 in rebuilding. The generic allocation chain is
also more prominent in stable mode. These profiles identify overhead paths;
they do not partition the invocation difference into wall time.

The second variant recovers most of the retained-graph regression, but remains
2.27 times as slow on the original property and doubles invocation time on the
interleaved case, where process peak RSS grows by about 83%. The tested arena
and free-span policy therefore fail the heap gate for a reference migration.

## Correctness

The second variant passes 289 shared native runtime tests in each mode, three
heap tests in stable mode, and 21 native continuation tests in stable mode.
Those runs enable heap verification, barrier assertions, and register allocator
verification. The stability test checks growth, collection, reuse and rejection
of the retired identity. Existing relocation tests continue to assert relocation
in compacting mode and exact address preservation in stable mode. All 45
declared C stubs pass with warnings denied. These are local tests.

## Packed offset references

The local `milky/gc-direct-offsets` branch adds
`WASMOON_EXPERIMENT_OFFSET_REFS=1`. The flag selects a separate JIT artifact
identity. It works with either the existing compacting heap or the experimental
stable heap. The low word retains the object identity. The high word carries a
tag and an aligned offset. Native allocation and Store-to-JIT conversion both
produce the packed form.

A JIT projection validates the live identity in a directory indexed by the
offset and computes the object address from the heap base. Exact structure
projections validate the requested field count and prefix shape. Numeric
arrays retain width and per-access bounds checks. A subtype, legacy layout,
or rejected offset still uses the complete checked helper. The compacting
heap updates the directory as objects move. A stale offset resolves through
the unchanged identity, including when another object occupies the old slot.
The stable heap rejects a mismatched offset. Collection, root publication, and
write barriers continue to use the stable identity. The native borrow verifier
still checks every path to the resulting address use.

Eight balanced cold-process rounds per input on macOS ARM64 returned the
expected value in all 96 processes. Times are median invocation times after
JIT installation. The compacting and stable ID-only controls use separate
release binaries from the same committed base. The two packed configurations
use the same experimental binary.

| Input | Compacting IDs | Compacting offsets | Stable IDs | Stable offsets |
| --- | ---: | ---: | ---: | ---: |
| Original parse_double, 20,000 cases | 1.502 s | 1.472 s | 3.479 s | 3.425 s |
| Alternating two structures, 24 million field reads | 29.89 ms | 51.64 ms | 30.13 ms | 51.44 ms |
| Retained graph, 2,097,152 nodes and 100,000 churn iterations | 109.65 ms | 108.43 ms | 114.09 ms | 113.09 ms |

On the original input, compacting offsets increased median cold compiler time
from 0.893 s to 1.127 s, process wall time from 2.523 s to 2.679 s, and peak
process RSS from 265.9 MB to 293.9 MB. The emitted ARM64 body for
`parse_decimal_from_view` grew from 8,668 to 18,080 bytes. Both ARM64 and x64
emit the direct address path alongside the checked fallback. With the
experiment disabled, the ARM64 machine bytes for the field-read fixture
match the committed base.

A separate instrumented build counted executed helper entries on the original
compacting-heap input. Structure projections fell from 65,498,857 to
3,887,610 and array projections from 27,235,172 to 521,735. The field-read
fixture fell from two structure helper entries to zero across 24 million
reads. Both measurements ran the same asserted inputs. The counters were
excluded from timing.

The candidate passes strict native checking for the affected packages, 45
native C stub checks, 217 JIT package tests, and the targeted stable-slot reuse
and moving-relocation regressions with heap, barrier, and register-allocation
verification enabled. Both packed modes pass all 633 assertions in the 17
Core GC spec files in each execution mode. x64 was checked through code
emission. The performance results support keeping this as an opt-in experiment.

## Selective projection tuning

The offset mode retains the existing bounded view cache for references likely
to repeat in a loop. This includes function parameters and fixed VMContext
slots in loops without explicit context writes or allocation. Cache misses
still take the checked path, including after a poll. Loop-carried references
and freshly allocated references keep the offset path. Giving all bounded
cache sites priority recovered the field-read workload but regressed the
retained graph. The selective policy recovered both.

Offset admission now uses one published directory pointer. Full GC
verification leaves the pointer null. The occupied-slot encoding keeps
zero identities from matching an empty entry while allowing one identity
comparison. The tag, live-slot check, shape checks, and array bounds remain.

Six balanced cold rounds per input on macOS ARM64 used the same
self-checking Wasm binaries in all configurations. The default and initial offset controls
use commit `1153f671` with the experiment off and on respectively.

| Input or phase | Default | Initial offsets | Selective offsets |
| --- | ---: | ---: | ---: |
| Original parse_double invocation | 1.480 s | 1.448 s | 1.407 s |
| Original parse_double native compilation | 0.833 s | 1.063 s | 1.019 s |
| Original parse_double process wall time | 2.400 s | 2.610 s | 2.512 s |
| Alternating field reads | 29.83 ms | 50.24 ms | 29.36 ms |
| Retained graph | 110.87 ms | 104.30 ms | 104.05 ms |

The field-read machine code matches the default byte for byte on ARM64
and x64. The ARM64 `parse_decimal_from_view` body shrank from 18,080 to
17,048 bytes. Its x64 counterpart shrank from 44,654 to 41,642 bytes.
Offset mode remains opt-in because the original workload still takes
longer end to end than the default.

## Bound layouts and bounded expansion

The next offset revision prepares a table from the instance's private type map
and the heap's immutable layouts. A published entry pairs the exact typed
header (canonical identity and field count) with the physical prefix. The JIT
still verifies the packed reference and live slot, the typed header, and the
compiled prefix before it produces a view. Heap changes revoke the binding.
Borrowed mutable type maps, missing layouts, allocation refusal, debug
verification, and mismatches use the checked helper. Array width and bounds
checks and the borrow verifier are unchanged.

Binding alone reduced the cold compiler median from 1.033 to 0.985 s and
invocation from 1.410 to 1.382 s in the first six-round comparison. The
compiler still emitted a checked fast/slow split at each projection. Restricting
expansion to loops and small accessors recovered another 92 ms of compiler
time in a second round, while losing 44 ms of invocation time versus binding
alone. Using immediate shifts and reusing the published heap/directory
admission then shortened the expanded path. Expansion uses the function's
control flow and projection count.

The final comparison used seven balanced rounds on macOS ARM64, with fresh
processes and independent cold caches. All 147 processes returned the expected
value on the same three Wasm binaries. The previous build is `64fb4849`.
The new build adds eight bytes per native context. Wasmtime 49.0.1 uses
serial compilation and its copying collector. V8 14.1.146.11-node.14 uses
eager optimizing compilation with one compilation task.

| Input or phase | Previous default | New default | Previous offsets | Bound offsets, compacting | Bound offsets, stable | Wasmtime | Eager V8 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Original parse_double compile | 809.74 ms | 805.11 ms | 986.01 ms | 858.23 ms | 858.36 ms |  | 432.32 ms |
| Original parse_double invoke | 1.443 s | 1.452 s | 1.380 s | 1.389 s | 3.305 s |  | 0.756 s |
| Original parse_double process wall | 2.328 s | 2.325 s | 2.458 s | 2.318 s | 4.229 s | 2.462 s | 1.237 s |
| Alternating field reads, invoke | 29.39 ms | 29.30 ms | 29.32 ms | 29.38 ms | 29.19 ms |  | 6.05 ms |
| Alternating field reads, process wall | 34.42 ms | 34.31 ms | 34.21 ms | 34.21 ms | 33.96 ms | 13.31 ms | 52.81 ms |
| Retained graph, invoke | 106.46 ms | 107.30 ms | 100.09 ms | 99.31 ms | 103.60 ms |  | 129.45 ms |
| Retained graph, process wall | 114.96 ms | 115.88 ms | 109.27 ms | 108.23 ms | 112.89 ms | 545.02 ms | 182.35 ms |

Wasmoon reports native compilation separately from decode and validation.
V8's compile phase includes validation. Wasmtime is timed at the process
boundary. On the original property, the paired median whole-process change
is a 5.72% reduction versus the previous offset path and a
0.29% reduction versus the previous default. Invocation is close to the
previous offset path. The whole-process ratio to eager V8 is 1.87x. The
stable heap takes 2.38x as long as compacting during invocation on this input.

The emitted `parse_decimal_from_view` body is 11,840 bytes on AArch64 and
28,140 bytes on x64, down from 17,048 and 41,642 bytes. The alternating
field-read body remains byte-identical on both targets. With offsets disabled,
both inspected functions match the control machine bytes. The evidence
supports keeping the compacting offset path opt-in.

A separate three-round screen covered zero and nonzero i32 arrays, four-element
arrays, v128 initialization and a mutated large reference array. All 60
processes returned the expected value. Invocation medians changed by -1.94%
to +4.61% versus previous offsets. A nine-round repeat of the four-element
case gave a paired median invocation increase of 1.57%, with pairs ranging
from -4.25% to +5.04%. These samples do not establish an array speedup.

Local validation passed all 3,292 native tests and 45 C stubs with warnings
denied. The rebinding regression passed in both offset modes, and all 633
Core GC assertions passed in each JIT/interpreter and compacting/stable
combination. AArch64 execution and x64 code emission were checked on macOS.

## Indexed array payloads and integer selection

Two invocation-only sampling windows on the original `parse_double`
property put about 72% of main-thread leaf samples in JIT code and 10% in
the three array and struct projection helpers. A separate build that
recorded linked function ranges attributed 48–50% of main-thread samples
to `Decimal.left_shift` and `Decimal.right_shift` together. The hot byte
array accesses spent three instructions forming each element address
before the load or store. The same function in eager V8 used indexed byte
accesses. Both V8 and Wasmtime emitted `msub` for the multiply and
subtract in the decimal remainder.

In offset mode, the memory rewrite exposes a numeric array payload only
from a width-matched element view on the guarded edge. The verifier checks
that provenance and the existing borrow lifetime. Length still comes from
the metadata view. This separates the 16-byte prefix from the element
offset, so selection can pass the base and the zero-extended index directly
to a target memory operand. The original fallback and its traps remain
available. Reference stores continue through the existing barriers.

The native selector also folds single-use multiply/subtract and logical
shift/add. AArch64 uses `msub` and `add ... lsr`, while x64 emits the
equivalent separate operations. The offset admission path extracts the
same 27-bit slot once for both the identity-directory lookup and the heap
address. The tag predicate, directory identity check, typed layout check
and slow path remain in place.

In the emitted AArch64 body for `Decimal.left_shift`, an indexed
`ldrb` or `strb` replaces the four-instruction byte access sequence.
The reciprocal quotient adjustment uses a shifted add without a separate
shift. `Decimal.left_shift` shrank from 3,640 to 3,592 bytes and
`parse_decimal_from_view` from 11,840 to 11,408 bytes.
`Decimal.right_shift` grew from 3,388 to 3,472 bytes.

Allocation-time reference packing, width specialization alone, and
cloning the loop to lift the view guard were tested separately. The
allocation and width changes did not improve the property reliably. Loop
cloning saved about 3 ms in a four-round screen and increased code size.
Keeping array length opaque put a helper call back inside the hot loop.
These variants were discarded.

Seven rotated cold rounds on macOS ARM64 measured the original seed-37
property with all 20,000 assertions. Each engine received the same Wasm
binary (`fb7bf21507c21de4ffb79126f94cc0846314bd0b03c33060a533f15afe441db1`).
All processes returned the expected result. The previous offsets include
the bound-layout changes above. Wasmtime 49.0.1 ran serially with its copying
collector and cache disabled. V8 14.1.146.11-node.14 used eager optimizing
compilation with one compilation task.

| Phase | Previous default | Previous offsets | Indexed offsets | Wasmtime | Eager V8 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Compilation | 823.81 ms | 869.48 ms | 858.68 ms | | 448.55 ms |
| Invocation | 1.462 s | 1.405 s | 1.377 s | | 0.781 s |
| Process wall | 2.356 s | 2.349 s | 2.308 s | 2.417 s | 1.277 s |

Wasmoon measures native compilation separately from decode and validation.
V8's compile timer includes validation. Wasmtime is timed at the process
boundary. Versus the previous offset build, the paired median reductions
were 1.92% in invocation and 1.51% in process wall time. Six of seven
rounds improved on both measures. One slower round remained in the results.
Invocation still takes 1.76x V8 and process wall time takes 1.81x. Indexed
offsets remain opt-in.

In seven cold rounds of alternating field reads, the invocation medians
were 29.35 ms before the change, 29.80 ms after it, and 6.07 ms in V8.
The corresponding process wall times were 35.40 ms, 35.65 ms, and
13.76 ms in serial Wasmtime. The graph with 2,097,152 surviving objects
and 100,000 churn iterations varied much more in the mixed-engine screen.
In a separate 13-round comparison, its paired median invocation increased
1.38% from the previous offsets and the process user CPU median change
rounded to zero.
Both emitted AArch64 function bodies in the field-read workload match
the previous offset build byte for byte.

A nine-round Wasm 1.0 control ran 409.6 million wide products per
invocation with asserted checksums and offsets disabled. The paired median invocation change
was +0.11% versus the previous build. Process wall medians were 0.698 s
for the new build, 0.811 s for serial Wasmtime and 0.850 s for eager V8.
These measurements cover the listed workloads.

The final build passed 3,293 native tests and 62,563 Core spec assertions
in each of the default interpreter and JIT runs. Both offset heap modes
passed the 633 GC spec assertions in each execution mode, plus the
focused offset and heap-rebinding tests. The changed packages passed
strict native checking. The full-workspace strict check reproduced the
baseline WASI HTTP cancellation warning. Local execution was AArch64.
The x64 target was checked through emission.
