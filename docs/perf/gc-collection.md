# Native GC discovery and identity retirement

Tracking: [ISS-684](../../issues/ISS-684.md). Local macOS ARM64 release
measurements compare frozen `fef3fa05` binary `1d31661547fb` with explicitly
dirty candidate `b2fdd81c11eb`. Moon 0.1.20261021 / moonc 0.10.17 builds both.
This is a root-discovery optimization, not a collector replacement or platform
acceptance. Guest identities, layouts, tracing, thresholds and quotas are unchanged.

## Cause and change

Precise collection counted and copied pre-marked payload roots using two complete
live-identity walks. JIT allocation first marked active roots, although the
precise coordinator already copies the same active frames, exceptions, spills
and root scopes. This duplicate discovery was proportional to the allocated
objects, even when almost all were dead.

A private heap hint now proves when no payload headers are marked. Both marking
writers set it; sweep, abort and rollback clear it after clearing all retained
header marks, before completion callbacks. Precise JIT collection uses its existing
execution-root snapshot instead of pre-marking those activations. Conservative
collection keeps its marking path. Explicit and parked roots and marked exception
and continuation arenas are always included, irrespective of the hint.

Manual marks still seed the embedding visitor. This matters for edges leaving a
native typed graph: retaining the marked parent alone does not keep an untyped
child alive. Public regressions cover this boundary and marks created by ordinary
completion, abort and rollback callbacks. A low-level regression covers the
legacy C marker. Omitting either marking writer's hint update makes the matching
child-preservation control fail. The heap verifier also rejects an untracked mark.

## Attribution and uninstrumented measurements

Disposable counters on the current pinned-Core property report 15 collections,
52,018,314 seed candidates / 56.9ms CPU and 26,009,157 sweep candidates / 68.4ms.
Only 375–386 objects survive each collection. These diagnostic CPU counters
identify work; they are not before/after performance samples.

Five serial cold AB/BA pairs per input use unchanged self-checking guests and
independent caches, without concurrent builds or profiling. Every invocation
returns 1. Median invocation time in milliseconds:

| Workload | Parent | Candidate | Reduction |
| --- | ---: | ---: | ---: |
| Ten million 4-element arrays | 250.527 | 230.016 | 8.2% |
| Ten million 1-element arrays | 275.357 | 255.616 | 7.2% |
| Ten million 17-element arrays | 311.852 | 282.935 | 9.3% |
| 32768-node graph and 100000 churn iterations | 41.888 | 39.573 | 5.5% |
| Core parse_double, 20000 checked iterations | 1744.389 | 1696.449 | 2.7% |

Large-array controls remain correct; no material RSS or compilation improvement
is claimed. A separate 32 MiB retained reference-array control remains essentially
unchanged. The hint-only intermediate improves short-array allocation but leaves
parse_double unchanged; removing redundant precise pre-marking supplies the latter
improvement. No intermediate experiment remains in source.

The property was freshly built from Core 7547b846d38de3efa5509cb1b74ffb7ed9a4a3d1.
Its extracted guest SHA256 is
d256b1ab6b9a310e8240fca61bf9972e73978cc3cf0506ed886f183c4962bb31.
The current toolchain differs from the original issue artifact; do not combine
these timings with the earlier property tables. `benchmark_gc_workloads.py`
reproduces array/graph controls (`--scale 100` for short arrays, `--scale 10` for
the graph); `benchmark_parse_double_gc.py --samples 5 --count 20000` extracts the
same property from a supplied pinned Core artifact. All raw profiles, sources,
samples and caches stay in automatically cleaned OS temporary directories.

## Validation

Ordinary and all-three-verifiers native 3118/3118, wasm 1464/1464, strict checks
on both targets, info/fmt, C44, module boundaries and generated MSVC bridges pass.
Core native interpreter/JIT each pass 258 files/62563 assertions; Component each
passes 59 files/1385 commands without skips, with all three verification flags.
Fresh isolated macOS ASan/UBSan passes 322 tests, event-loop execution and both
ASan positive controls. That sanitizer build is explicitly dirty fef3fa05-based
local evidence; macOS cannot establish Linux LSan or Windows/x64 acceptance.

## Batched retirement of dead identity pages

The follow-up to 4ab8e41d adds a conservative mark hint to each identity page.
The two header-marking paths share one private setter. Sorted live identities
and verified exact page populations identify each page's traversal group.
Wholly unmarked pages retire their identity metadata once; marked pages retain
individual header checks and retirement. Allocation windows and payload-view
hints are cleared before page release. Stable identities, quota accounting,
bounded free-list bookkeeping, manual marks and rollback remain unchanged.
This adds four private bytes per identity page, with no public API or artifact
layout change. It is not a generational collector.

Dead payload headers still become FREE before their page is released. Omitting
these writes initially regressed large zero arrays 5–17%. Matching allocator
alignment did not remove the regression. A runtime toggle in the SAME binary
isolated the missing writes: one-million zero-array invocation 316.237->290.200ms
when header cleanup was restored. Specific cache/TLB contributions are unproven.
All diagnostic toggles and alignment annotations were removed. Header cleanup
still visits dead objects; only identity metadata retirement is batched.

Five serial AB/BA pairs freeze parent b2fdd81c11eb and final 276e7c91450f. Median
invocation milliseconds:

| Workload | Parent | Batched metadata |
| --- | ---: | ---: |
| Ten million 1-element arrays | 254.870 | 236.191 |
| Ten million 4-element arrays | 229.792 | 213.129 |
| Ten million 17-element arrays | 282.889 | 272.519 |
| Current Core parse_double | 1694.613 | 1653.034 |
| Retained graph | 39.652 | 39.053 |

The final 100000-array zero/nonzero/vector controls are approximately unchanged.
A separate five-pair 10x allocation-length run gives 282.246->290.053ms for zero
arrays and 390.251->399.820ms for vectors (2.5–2.8% slower); nonzero arrays are
395.358->394.442ms. This is retained as a small-object/real-property throughput
trade-off, not a universal win. RSS and compilation do not materially improve.
No sample or rejected variant is silently removed from these comparisons.

The public page-boundary regression preserves sparse survivors across three
rounds of 4097 allocations in both root modes, checks old survivor death, stable
identity numbering and subsequent allocation. Omitting page marking fails both
this test and the native-parent/untyped-child test. Ordinary/verified native 3119,
wasm 1464, strict checks/info/fmt/C44/audits, Core 258/62563 and Component 59/1385
per engine pass. Fresh isolated ASan/UBSan 323 plus event loop and both positive
controls pass on explicitly dirty 4ab8e41d sources. Subsequent clean086be748
run40127134073 establishes Linux LSan and Windows acceptance; see ISS-685.


## Prepared array constructors

[ISS-686](../../issues/ISS-686.md) reuses the canonical typed initializer through
non-collecting scalar/vector constructors. Admission uses the existing prepared
payload/identity window and excludes quotas, unknown/debug/failure controls,
growth and collection. Refusal returns zero without allocator mutation; the
original collecting call then stages its roots and preserves trap ordering.
Successful initialization completes before publication. No new tracing policy,
field layout or duplicate allocator is introduced.

Wasmoon explicitly opts into the new helper ABI. Other compiler embedders retain
the existing allocation contract by default. A private sixteen-site function
budget bounds the added CFG; large straight-line initializers retain the original
path. Struct/array expansion limits share one inspection pass. Successful calls
jump straight to the result join, without an empty success block.

Five serial AB/BA pairs compare frozen `086be748` binary `276e7c91450f` with dirty
candidate `3c37876afdc2`, using the same self-checking inputs and toolchain as above.
Median invocation milliseconds:

| Workload | Parent | Prepared constructor |
| --- | ---: | ---: |
| Ten million 1-element arrays | 236.875 | 178.024 |
| Ten million 4-element arrays | 213.584 | 155.023 |
| Ten million 17-element arrays | 273.298 | 208.739 |
| Million 4096-element zero arrays | 287.852 | 283.237 |
| Million 4096-element nonzero arrays | 390.981 | 382.922 |
| Million 1024-element high-word vectors | 385.437 | 372.943 |

Current Core property 1653.104->1640.416ms, graph 38.951->39.489ms and retained
reference-array 15.885->15.684ms do not establish improvements. RSS is unchanged.
Small modules pay roughly 20–60us extra compilation. Nine complete cold compile
pairs give auth3 42.019->42.495ms, Argon2i 74.354->73.471ms and the current
property 851.900->848.708ms; no material compiler gain is claimed.

The initial unbounded form expanded 100 straight-line allocations from 24.4KB to
37.5KB and compilation 2.1->3.8ms. After the budget, 100/500/1000-site artifacts
are byte-identical to the parent and compile in 2.114/13.584/36.390ms versus
2.129/13.780/36.588ms. Public regressions cover both targets at 16/17/100 sites,
exactly one collecting safepoint, and reference fills across identity pages,
collection, injected failure and subsequent reuse. Removing the split lowering
fails the new code-generation regression. All raw data stays in temporary storage.

Ordinary/all-three-verifier native3122 and wasm1464 pass, as do strict checks,
info/fmt, C44 and module/MSVC audits. Core258/62563 and Component59/1385 per native
engine pass with verification and again with the prepared path enabled. Fresh
isolated ASan/UBSan324, event loop and both ASan controls pass on explicitly dirty
086be748 sources (binary2deb04c11bcc); Mac LSan is unavailable. Both-target
selection is not a substitute for actual x64 execution; exact-head CI is pending.
