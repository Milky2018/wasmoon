# Precise native generational collection

Tracking: [ISS-689](../../issues/ISS-689.md),
[ISS-690](../../issues/ISS-690.md), [ISS-691](../../issues/ISS-691.md).
This extends the native mark/sweep/compact heap. Root coordination and collection
policy remain MoonBit; portable Wasm execution and interpreter semantics are unchanged.

## Evidence and lifetime contract

A regex CPU sample attributes about 46% of main-thread work to native graph
traversal/marking. Independent lifetime counters show roughly 9% new-object
survival, 99.9% mature survival, and 90% mature revisits at n=2100. Instrumented
timings are excluded from the final comparison.

Only allocation-budget collection can choose the young path. A precise provider
opts into separate read-only young-root expansion. Declining recomputes complete
major seeds. Explicit collection, rollback, physical-allocation retry, quotas,
untyped history, auxiliary arenas and incomplete roots preserve their complete
collection or failure contracts. The Store also declines while managed auxiliary
metadata or an explicit trace exists. Incomplete discovery never permits sweeping.

Stable identities partition payload and live identities into a mature prefix and
a young suffix. Existing reference-write barriers remember mature owners without
allocating, collecting or reentering, including between execution scopes. Every
dirty owner is independently seeded. Young tracing skips other mature objects;
sweep/compaction touches the suffix and promotes survivors before callbacks.
Identity numbering, quotas and physical-borrow/safepoint rules are unchanged.

Large reference-bearing objects additionally receive optional 256-field cards
while compacting survivors. Sparse writes then scan dirty ranges, rather than the
whole object. Metadata allocation failure retains complete owner scanning. Small
objects and unknown-index writes retain the complete-owner path. All reference
writes still count and assert; the verifier checks every mature-to-young edge
against both owner and card coverage. Retiring identities/pages releases metadata.
Aborted attempts preserve dirty edges, and generation invalidation precedes major
reclamation/rollback. A separate attempt epoch expires young graph handles after
success or abort; an old worklist cannot claim completeness during a later attempt.
Ordinary read-only graph queries remain complete.

The nursery allowance is 16 MiB. A major follows at most 64 young collections
(1 GiB of nominal nursery allowances), or earlier mature growth. Separating these
limits avoids multiplying full scans when reducing nursery size. Oversized
objects retain ordinary admission and growth rules; this is not a new quota.
Periodic majors retain the nursery allowance. Explicit and declined collection
retain the previous live-set-sized allowance and minimum. A real 72 MiB regression
checks this transition, including both full fallbacks.

Segment constructors now use the shared canonical allocator, retaining their
single non-collecting attempt and caller checks. Unknown embeddings keep wide
slots. Dense collection also exposed numeric allocation operands being mistaken
for native exception handles. Root materialization now replaces only known scalar
operands with null using the existing immutable layout; reference operands and
unknown layouts retain their contracts. Exception validation stays strict.

## Uninstrumented comparison

Five serial cold-cache pairs alternate order and retain all guest assertions.
The current Core7547b846 regex test and Moon0.1.20261021 toolchain are pinned.
Parent is frozen cf7c3569 binary e85e34647dee; the final explicitly dirty d2ebec7b-based
implementation binary is 22a478d4f08e. Verification flags are absent from timing.
All 155 fresh processes across fourteen workloads pass. Complete cached artifact
bytes match between variants for every compared input and sample.

Invocation excludes compilation. Peak RSS covers the entire fresh process,
including compilation and teardown; MB below means decimal megabytes.

| Workload | Parent invoke | Change invoke | Parent peak RSS | Change peak RSS |
| --- | ---: | ---: | ---: | ---: |
| Regex GC n=700 | 2.017s | 1.574s | 532MB | 316MB |
| Regex GC n=2100 | 23.729s | 18.684s | 2453MB | 2114MB |
| 32K retained nodes, 1M churn iterations | 366.7ms | 201.9ms | 80MB | 82MB |
| 2M retained nodes, 100K churn iterations | 624.0ms | 110.1ms | 445MB | 311MB |
| Static 128 MiB reference array | 194.1ms | 40.6ms | 277MB | 278MB |
| Sparsely mutated 128 MiB reference array | 194.0ms | 40.9ms | 278MB | 279MB |

Paired 95% invocation log-ratio intervals are 0.775–0.787 and 0.785–0.791 for
the two regex sizes. Their compilation medians are 379/382ms and 378/382ms;
intervals include no change. Large zero/nonzero i32 arrays and v128 arrays improve
about 27/16/13%. Tiny arrays differ by about -1% to +2%, with the latter intervals
crossing no change. Parse-double is approximately flat (1640/1644ms). These are
incremental runtime comparisons against the already optimized PR head, not an
aggregate corpus speedup or new Wasmtime/V8 results.

The rejected coarse-owner version regressed sparse arrays by 62% because it
rescanned whole arrays. Removing card recording reproduces child loss, and the
strict verifier identifies the uncovered edge. A 64 MiB nursery still regressed
the small graph by about 14%. Reducing nursery size while retaining a fixed
16-cycle major interval regressed large regex execution; independent cadence
removes that coupling. An earlier periodic-major allowance bug also doubled
physical capacity; the scoped budget regression protects its repair. None of
these rejected variants is the final implementation.

The maintained generator retains the large graph and reference-array fixtures:

```sh
python3 scripts/benchmark_gc_workloads.py --wasmoon /path/to/wasmoon --samples 5 --case large-survivors-and-mutation
python3 scripts/benchmark_gc_workloads.py --wasmoon /path/to/wasmoon --samples 5 --case mutated-large-reference-array
```

These commands additionally run serial-compilation Wasmtime and optimized V8;
those new executions are distinct from the parent/change comparison above.

## Validation boundary

Eighteen generational and six card regressions cover mutation, cycles, independent
roots, sparse/partial/dead pages, quotas, faults, visitor replacement, reentry,
closure, rollback, budgets, failed discovery and escaped worklists. Separate public
regressions cover canonical segment representations and numeric root aliases.

The combined source passes native3151/3151 both ordinarily and with all three
verifiers, Wasm1465/1465, strict checks on both targets, info/fmt, C45 and module/
MSVC audits. The independent root repair and segment repair also pass clean
native3126/3126 and3127/3127, each in ordinary and verified modes, with normal
commit hooks. Fresh sanitizer, integration and exact-head platform acceptance are
pending separately. macOS cannot establish Linux LSan or actual Windows/x64 execution.
Raw fixtures, profiles, measurements, builds and caches stay in auto-cleaned
OS temporary workspaces; no raw evidence is committed.
