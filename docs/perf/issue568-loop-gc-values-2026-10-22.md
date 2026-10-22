# parse_double: loop-invariant logical GC values

This continues the [explicit-heap helper work](issue568-heap-helpers-2026-10-22.md)
for [#568](https://github.com/Milky2018/wasmoon/issues/568). The accepted changes
reduce repeated work in the Wasm optimizer. Native heap representation and C
accessors are unchanged in this stage.

## Design

Two complementary transformations run at O2/O3:

- A struct read may leave a loop when its reference was checked before the loop,
  the referenced SSA value is invariant, and the field cannot change. Writes
  invalidate by field index across all possible aliases and declared types.
  Calls, polls, allocations and unknown effects inside the loop reject it.
  Successful allocations before the loop do not erase logical non-nullness;
  no physical address is cached across allocation or collection.
- A read without that proof stays at its first execution point. The loop carries
  a valid flag and its result as ordinary SSA block parameters. The first use
  performs the original read and trap; subsequent iterations reuse the value.
  This covers integer/reference struct fields and immutable array lengths.
  Zero-trip loops and conditional paths do not acquire speculative null traps.

Each CFG split rebuilds loop analysis before another transformation. In
particular, splitting one loop can move the terminator of another loop's
preheader. Reusing the old CFG produced an arity mismatch in a discarded
prototype. Expansion is bounded to eight cached reads per function, 1024
blocks for caching and a fixed loop-instruction work budget. Unsupported or
irreducible entries, branch tables and effects retain ordinary accesses.
Callsite source locations remain attached to the original query's slow path.

The policy remains Wasm-owned; generic MilkIR does not gain Wasm GC layout
knowledge. These passes share private read keys and alias rules in the existing
Wasm optimizer package. The existing shared optimizer serves CLI, Component, preflight and
explore. O0/O1, allocation admission, quotas, write barriers and GC/root
verification remain enabled under their existing contracts. Codegen revision
15 prevents reuse of revision-14 artifacts.

## Parallel phi verification

A new zero-trip regression exposed an existing allocation-checker defect.
Passing one value to two block parameters can legally give both names the same
physical home. Both the regalloc and VCode checkers renamed parameters
sequentially, destroying the source identity before checking later arguments.
They also represented a location with only one name.

Both checkers now validate incoming arguments before parallel renaming and
track equivalent names at each location. Copies preserve those names; a write
or clobber removes them, and control-flow joins retain only common names.
Positive tests cover either shared parameter being used. Negative tests still
reject different source bits sharing a home and uses after an alias is
overwritten. No allocation or root-protection check is disabled.

## Controlled comparison

The [receipt](issue568-loop-gc-values-local.json) records raw measurements,
source and binary hashes, counters and validation. Both Wasmoon variants were
freshly built with the same installed SDK: baseline is clean commit 5d468ed4,
accepted sources are the explicitly dirty tree based on that commit. Previous
receipts used an older SDK and are preserved as historical evidence.

The pinned Core revision, original Wasm bytes, seed, 20000-case property,
import isolation and result predicate are unchanged. All results are 1.
Each invocation uses a fresh cache; Wasmtime 49.0.1 uses
`-C parallel-compilation=n -C cache=n`. Three samples alternate engine order.
These are cold CLI times, including compilation and startup:

| Cases | Baseline wall / user CPU | Accepted wall / user CPU | Wasmtime wall / user CPU |
| --- | ---: | ---: | ---: |
| 1000 | 1.112 / 1.087 s | 1.059 / 1.036 s | 0.380 / 0.366 s |
| 20000 | 7.379 / 7.328 s | 5.966 / 5.921 s | 2.436 / 2.426 s |

Full-case wall time falls 19.1%, and the same-run wall ratio falls from 3.03x
to **2.45x**. Separate counter trials retire 164023633902 instructions in the
baseline, 127291726349 in the accepted implementation and 60857984978 in
Wasmtime: 22.4% fewer instructions, still 2.09x Wasmtime's count. RSS is
approximately 352 MB for both Wasmoon builds versus 71 MB for Wasmtime. This
stage does not solve the memory gap or establish Wasmtime parity.

The final sample's leading active leaves are array stores, array reads and
struct reads. Array length and TLS leaves are much smaller. The idle
`__sigwait` thread is excluded when interpreting the sample. Sampling does not
provide an additive attribution of the remaining 2.45x wall gap.

## Rejected experiments and measurement correction

A mechanical native inlining prototype duplicated dynamic identity/layout
checks and increased compilation cost. It is removed, along with its optional
reader interface, offset query and embedding package. No speculative physical
layout hint or additional runtime ABI remains.

An early exploratory helper mistakenly shared a persistent cache directory
across revision-14 candidates. Those intermediate timings are discarded and
must not be cited as speedup evidence. The accepted measurements above use the
standalone comparison script, with a new directory for every invocation and
recorded binary hashes. The array-length-only prototype is superseded by the
bounded logical-value cache; no separate prototype pass remains.

## Validation and remaining direction

- Native 2999/2999 with regalloc, GC and barrier verification; wasm 1417/1417.
- Native interpreter, JIT and actual wasm Core: each 258 files / 62563
  assertions, zero failures or unsupported cases.
- Component interpreter and JIT: each 59 files / 1385 commands, zero skips.
- Fresh isolated macOS ASan/UBSan: 274/274, both positive controls detected,
  system allocator and event-loop control passed. Local LSan is unavailable.
- Strict native/wasm, info/fmt, module boundaries, generated MSVC bridges and
  Python 178 tests with 54 existing platform skips pass.

Regression coverage includes first-use trap ordering, zero-trip null inputs,
aliased mutation, calls and allocation inside a loop, reference-valued caches,
repeated invocations, collection and quota release. Historical dirty-tree
receipts are not relabeled as clean commit or CI acceptance. Execution here
covers macOS ARM64, not x64, Windows or Linux LSan. Owned temporary sources,
binaries, builds, caches and profiles are removed after verification.

The next architectural experiment should expose a checked GC access region to
the compiler: validate an access view once on an executed path and keep it
only until a safepoint or embedding reentry. Direct array loads/stores then
need neither a C call nor repeated identity/layout resolution. That requires
sound host-entry type, alias and safepoint contracts; duplicating C helper
checks in emitted code is insufficient. Existing low-level interfaces are
subject to redesign when they prevent that contract, rather than treated as
permanent constraints. No such physical-address region is claimed by this
logical-value optimization.
