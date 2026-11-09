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
