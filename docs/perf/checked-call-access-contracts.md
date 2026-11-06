# Checked call and access contracts

Tracking: [#598](https://github.com/Milky2018/wasmoon/issues/598).

## Direct calls

The decoded module's mutable section containers and the optional compilation
mask are copied before progress callbacks run. A callback may mutate its caller's
inputs, but compilation uses the admitted body snapshot. Direct calls use the
same conservative effects in full and partial artifacts. Polls keep their
original charges, and physical borrows end at call and poll boundaries.

The [PR #582 checkpoint](https://github.com/Milky2018/wasmoon/blob/35b1d7930daa268d17d7438604fdde44829f2e37/docs/perf/checked-call-access-contracts.md)
records the retired region guards and transitive call summaries.

## Logical carriers and physical storage

A struct reference, callable reference and opaque reference remain different SSA
types. Their compact field storage is nevertheless one eight-byte reference
class. Checked field views must use that physical class for width and layout
proofs without erasing logical types. Reference writes retain the checked
barrier path; reference arrays retain their existing checked accessors.

The existing runtime helper verifies an exact physical field prefix, including
canonical type/subtype admission, width/reference shape and field span. A large
struct may therefore expose its completely checked first sixteen fields without
admitting its remaining suffix. The independent field validator rejects a
projection outside that prefix. Null/type traps, legacy slot adapters, verifier
mode and physical address epochs retain their existing behavior.

The existing 32-byte non-root cache records the actual object's complete
physical prefix, independently of the requested nominal type. Shorter compatible
prefixes share that admission. Publication requires the physical canonical
identity to agree with the current runtime identity. Exact physical access keeps
its existing behavior when these identities differ, but cannot publish a subtype
hint from that mismatch. The heap verifier checks the cached identity, span and
shape independently.

Every subtype hit consults the current Store relation. Generated code handles a
current immediate-parent edge; transitive relations use the complete checked
helper. The immediate-parent path requires both identities to be live indices
in the current registry. A parent sentinel or out-of-range entry cannot admit
a rebound local type. Parent replacement or clearing takes effect on the next
access without a cached nominal decision. Object type changes, collection,
growth, rollback, retirement and close retain their existing invalidations.

The frontend retains indexed-type finality in the validation context. Final
types select the compact exact-layout hit path, while missing finality metadata
keeps the general path. Both choices preserve the complete checked miss path.
The shared C leaf similarly keeps exact-key equality; prefix masks and current
subtype walks remain in its complete out-of-line path.

Access admission and allocation expansion have separate limits. Admitting a
callable/opaque field or a large object's prefix must not count an unsupported
allocation against another object's inline allocation budget. The allocator's
original complete-shape admission remains unchanged.

The distinction matters in ordinary MoonBit closure code: a callable field must
not prevent checked reads of the closure's other fields. Likewise, a 27-field
object must not exclude a checked read of field eight solely because its suffix
cannot fit the compact shape descriptor. These are layout admission decisions,
not permission to omit validation.

Projection selection also admits small acyclic accessors with at most 12
blocks, 64 live IR instructions and three candidate projections. A getter can
run repeatedly in its caller's loop even when it has no local loop. The same
checked misses, target budgets and address proofs apply. In a one-file
comparison on the original SDK28 flate blackbox and whitebox workloads, six
alternating measured pairs per workload reduce median paired process wall by
5.63% and 4.55%, respectively. All 32 processes, including warmups, preserve
their original test inventory and output. One measured blackbox pair is
0.33% slower and remains in the sample. This isolates the selection policy;
it does not measure the complete refactor against the parent.

A separate concrete type-test trial reused the live identity from that same
physical admission record and still checked the current Store relation.
All 24 processes preserve their test inventories, but its geometric mean
of paired case medians improves only 0.48%, below the declared 2% threshold.
Several measured pairs are slower. The trial is excluded; casts and field
accesses retain their separate checks.

## Read admission and allocation controls

The native adapter can opt into an ordinary-mode publication contract. The
Wasmoon provider publishes a struct or array cache entry only after a checked
helper admits it and the process verification setting resolves to ordinary
mode. That setting remains fixed once resolved. Verification mode cannot
populate the cache, so misses continue to use the complete helpers. Other
providers keep their explicit per-access gate by default.

The Wasmoon read path can then omit the separate mutable allocation gate on
each cache lookup. The reference, bounds, nominal type, field shape, borrow
epoch and fallback checks remain. Allocation still reads its mutable control
and honors fault injection. A regression warms both view kinds, injects
persistent allocation failure and checks the trap, the existing reads and
successful allocation after fault injection is cleared.

An isolated cold comparison changed only this read admission path. All
twelve original child pairs matched their selected tests and output. Median
paired wall reductions were 1.10% for builtin, 0.93% for JSON, 7.23% for flate
whitebox and 2.86% for immutable vector. The geometric mean of the four
ratios is 0.9693. This passes the private screen and does not establish a
complete-suite improvement.

## Root locations and validation

[Root publication contracts](root-publication-contracts.md) separates proved
noncollecting operations from root sites while retaining the existing frame
chain, ownership, parked-stack lifetime and nonlocal-exit markers. Unknown
collecting calls keep complete live-root publication. The rejected machine-home
prototype is recorded there; it is not part of the retained runtime ABI.

Negative controls must reject a forged call cost, foreign token, insufficient
credit, stale physical address and out-of-prefix field. A runtime control that
omits one live root must fail actual reclamation assertions. Original
callback, cancellation, fuel and quantum outcomes must agree across optimization
levels. Final admission requires independent matched measurements and complete
platform validation; source simplification and allocation counts alone are not
performance evidence.

## Complete serial Core comparison

The frozen refactor and parent `ee89e73c` use the same Wasmoon embedding
source. The two embeddings and the official V8 runner use SDK20261028. The original
`moon test --target wasm-gc -j 1` driver schedules one test job at a time;
V8's internal settings stay at their defaults. Each arm starts with a separate
empty cache. All nine runs execute the same 157 child selections and pass the
same 8,384 synchronous tests with identical output and unchanged Wasm inputs.

| Round | Official V8 (s) | Parent (s) | Refactor (s) | Paired change |
| --- | ---: | ---: | ---: | ---: |
| 1 | 19.672 | 213.394 | 206.669 | -3.15% |
| 2 | 18.516 | 202.993 | 204.719 | +0.85% |
| 3 | 18.424 | 202.595 | 202.432 | -0.08% |

The paired median is 0.08% faster; the median refactor-to-V8 ratio is 10.99×.
This fails the declared 2% improvement with no slower pair. The isolated
accessor gain therefore does not establish a complete-suite improvement.
In one instrumented whitebox compile, the same 1,264 functions take 1.116 to
1.343 seconds, with the largest increases in native construction and register
allocation. Code size rises 3.9% while reloads fall from 5,365 to 5,276.
This diagnostic measures one module and cannot partition the complete gap.

A separate phase observer on the parent attributes 101.76 of its 215.69
seconds to native compilation and 102.30 seconds to the execution phase.
Execution includes the downstream driver and runtime work after installation.
This is one diagnostic run, separate from the uninstrumented comparison.

The same observer was then paired on twelve original child selections. The
eight compile-heavy cases are the longest synchronous selections whose parent
compilation exceeded twice their execution time. The other four have the
longest parent execution times among the remaining synchronous selections.
Both arms preserve all 4,055 selected tests, expected panics and snapshots.

| Original selections | Parent compile (s) | Refactor compile (s) | Parent execute (s) | Refactor execute (s) |
| --- | ---: | ---: | ---: | ---: |
| Eight compile-heavy children | 17.003 | 17.785 | 3.068 | 3.064 |
| Four execution-heavy children | 3.445 | 3.579 | 58.647 | 53.972 |

The eight compile-heavy cases all compile more slowly. The four execution-heavy
cases save 4.68 seconds in aggregate, led by flate whitebox (28.023 to 24.146
seconds); strconv execution rises from 5.590 to 5.649 seconds. Selection is
intentionally biased toward phase extremes, and the results do not estimate
the complete-suite change. Improving one side of the gap leaves substantial
work on the other side. A hot access path must earn its extra code generation
cost, and eager full-module compilation needs a separate strategy.

### Complete comparison with ordinary read admission

A new frozen candidate adds the read admission contract described above.
The parent and official binaries, driver, 157 input hashes, invocation
inventory, deadlines and rotating order are identical to the initial
comparison. All nine fresh runs pass all 8,384 tests with identical stdout
and empty stderr.

| Round | Official V8 (s) | Parent (s) | Candidate (s) | Paired change |
| --- | ---: | ---: | ---: | ---: |
| 1 | 18.513 | 204.215 | 197.613 | -3.23% |
| 2 | 18.494 | 208.287 | 197.634 | -5.11% |
| 3 | 19.876 | 206.946 | 206.838 | -0.05% |

The paired median reduction is 3.23%. All three pairs meet or beat the
parent, including a near tie in the third round. The median paired ratio to
official V8 is 10.67×. These are end-to-end cold times for the complete serial
suite, including compilation, installation and execution. The comparison
admits the combined refactor and read admission change. The separate child
pairs above measure the isolated effect of read admission.
