# Logical memory and physical address epochs

The compiler must preserve two independent facts about a managed object:

- A logical read depends on the values written to its alias region.
- A physical projection depends on the current address epoch as well as the
  metadata used to admit its layout.

Collection can change the second fact while preserving the first. Reentry,
heap replacement and unknown calls can change both. Neither logical value
numbering nor a successful runtime type check extends a borrowed pointer's
lifetime.

## Contract and pipeline

Dialect-validated `ExtensionEffects.invalidates_addresses` ends the address
epoch independently of `write`. An extension with `pointer_region` produces a
physical address and depends on that epoch. Ordinary raw loads depend on it
too. Missing extension contracts retain unknown memory effects; unknown writes
invalidate all logical regions and the address epoch.

Wasm allocation retains its allocation, trap and collection effects, but does
not claim to write existing logical fields. Bulk array updates retain element
writes and address invalidation. Full polls and calls retain conservative
logical writes, reentry, suspension and address invalidation. Reference identity
comparison and the two representation-preserving external-reference conversions
have the same pure contract as their native comparison/forwarding implementation.

The ordinary dominator-scoped GVN carries an address version alongside alias
versions. CFG joins and loop backedges meet these versions independently.
Address invalidation is tracked after the memory precision budget expires.
Store forwarding records the post-store address version, including unknown
writes. LICM checks both alias writes and address invalidation before moving a
physical read or projection.

The existing logical optimization runs before checked GC-memory expansion.
Consequently, an already-read scalar or stable reference can be reused across
allocation. A later access that still needs memory obtains a new checked
projection. The subsequent physical optimizer cannot merge projections across
an address epoch. The independent GC borrow verifier continues to reject stale
addresses, escapes, unsupported pointer operations and invalid control tokens.

## Validation and limits

Tests distinguish reuse of logical values from forbidden reuse of physical
addresses, including conditional collecting backedges, exhausted analysis
budgets, raw load CSE, store forwarding and LICM. Wasm-specific controls retain
allocations, alias-write invalidation, full polls and the independent borrow
proof. A public interpreter/JIT comparison exercises allocation pressure followed
by aliased mutation.

This contract does not add interprocedural call summaries, speculative layout
admission, broader inlining, a new GC, region budgeting or final-register stack
maps. Those decisions need separate workload evidence. In particular, removing
one redundant logical read does not establish a whole-program speedup. Codegen
revision 32 prevents reuse of artifacts produced by the previous optimizer.

## Matched performance checkpoint

Both variants use fresh builds of the unchanged `ed848ac5` downstream runner,
the October 23 SDK, and parent `d36b0d9d`. The original ten-call input is
SHA-256 `44bcb057bbd6ebaa86e96dc912b2d9e01002659d72e2fb76afda97b8e14acc5c`.
Each round retains five alternating parent/candidate pairs per input, fresh
processes, separate empty caches, all assertions and every sample. Builds,
profilers and other benchmarks are absent during retained timing.

| Round/input | Parent median (s) | Candidate median (s) | Median paired change |
| --- | ---: | ---: | ---: |
| Four-engine round, zero calls | 0.901257 | 0.912143 | +0.153% |
| Four-engine round, ten calls | 2.499622 | 2.458054 | -0.539% |
| Independent confirmation, zero calls | 0.852913 | 0.848515 | +0.421% |
| Independent confirmation, ten calls | 2.321132 | 2.331109 | -0.046% |

The first ten-call round improves all five pairs; the independent round is
mixed. Median paired changes are not ratios of separately computed medians.
The +4.15% startup outlier remains in the first round. Process RSS is essentially
flat. These results do not establish a material original-workload speedup.
The change repairs the optimization contract and demonstrates removal of a
class of redundant reads; the dominant object-projection cost remains unresolved.

Official SDK V8 and serial Wasmtime 49 medians in the first round are 0.416381 s
and 1.319360 s for ten calls. All 60 measured processes across both rounds exit
successfully with empty stdout, and all owned caches are removed. Whole-process
time includes compilation, instantiation, GC, scheduling and teardown; it is
not isolated guest execution. These local measurements do not establish
performance on x64 or Windows.
