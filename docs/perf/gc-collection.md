# Native GC root discovery

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
