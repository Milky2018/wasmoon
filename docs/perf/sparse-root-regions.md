# Guarded object reads and sparse call frames

Tracking: [ISS-724](../../issues/ISS-724.md).

The remaining object-access cost crosses two compiler boundaries. An empty
conditional dispatch can hide a successful check behind a block parameter.
Repeated inlined polls then end each physical object view. Finally, a function
with only a few live references at collecting calls still maintains persistent
shadow slots along its pure paths. Expanding accessors alone does not address
these interactions.

## Control flow and physical views

Generic jump threading now resolves an empty conditional dispatch when the
incoming edge supplies its constant condition. It rewrites the selected edge's
arguments and rejects parameters used outside that dispatch. It preserves all
instructions, bounds conditional traversal and never caches an argument-dependent
answer as a block-only answer.

Small acyclic functions with repeated reads can retain physical views across
their original polls after a successful budget guard. Admission requires a fully
reachable DAG, compatible control layouts, at most 24 blocks, 64 instructions
and eight polls. Every source poll becomes a checked charge at the same source
position in the admitted clone. The complete original CFG remains the fallback
for callbacks, unavailable controls and quantum boundaries. Instructions that
invalidate credit prevent any later admitted charge.

The existing independent credit verifier checks every route to each charge.
The physical-borrow verifier still rejects stale views, side entries, reentry,
moving collection and borrowed block arguments. Generated struct/array cache hits
are allowed in these guarded regions as well as the existing bounded loops.
Exact cache keys, null, nominal identity, shape, width and bounds checks remain;
every refusal selects the original checked helper. Cache lifetime and heap
layout are unchanged.

## Root ownership at calls

The generic call ABI can opt into a positive sparse-root capacity limit. Wasmoon
uses four live references. The producer additionally requires every nonempty
rooted site to be suitable for this cost model; unknown calls, allocating sites
and larger sets keep their existing whole-function frames. Other providers
default to the previous behavior.

A selected function reserves one reusable header, root array and mask on its
own stack. Immediately before each rooted call it writes the exact live prefix
and mask, then publishes the existing function-frame protocol. The frame stays
registered while that call collects, reenters or parks, and is unlinked after
return. Published capacity bounds the precise prefix even when later sites reuse
less storage. Pure paths have no persistent root-definition stores or published
frame. No heap-owned scope node or root-array copy is introduced.

Regular frames and call-site frames share publication and unlink lowering.
Existing checked current-activation admission, chain-head traps, unwind markers
and parked-source enumeration apply to both. Duplicate SSA root transport is
omitted only after frame ownership is established; call-site and argument-root
metadata remain. Returns-twice restrictions and generic caller-scope behavior
are preserved. Native ABI and artifact format are unchanged; codegen35 rejects
revision34 cached machine code.

## Correctness and measurement

Compiler tests cover argument-dependent dispatch, complete poll fallback, budget
credit, guarded view selection and reuse of a 65-root frame for a one-root site.
Shared ordinary/sanitizer tests exercise O0/O2/O3 collection, detached children,
parking, continuation cancellation and quantum boundaries. An independent
negative control publishes an empty live prefix while retaining all stores and
link lifetimes: collection incorrectly reclaims the parked child and the public
test fails. Exact restoration passes with all three verification flags.

Measure the object-only and combined object/root arms independently against the
same parent. Whole-process timings include cold optimized compilation, startup,
execution, collection, scheduling and teardown. Hot-module improvements do not
establish a corresponding complete-suite improvement or pure guest-execution
ratio. Preserve the official driver's original assertions, selections and
`-j 1`; that option serializes test executables and leaves V8's internal defaults
unchanged.

One warmup triplet and five measured rotating triplets per original SDK28 hot
module compare parent `5dc99486`, object regions alone, and the combined sparse
frame candidate. All 108 fresh processes preserve the original assertions and
empty independent caches; all measured combined and incremental root pairs
improve. Median paired whole-process changes are:

| Original module | Object regions / parent | Combined / parent | Combined / object regions |
| --- | ---: | ---: | ---: |
| flate blackbox | -12.11% | -17.00% | -5.60% |
| flate whitebox | -1.57% | -5.09% | -3.39% |
| strconv | +0.03% | -0.76% | -0.59% |
| immut/vector whitebox | -1.57% | -2.75% | -1.22% |
| edit-distance | -8.06% | -12.12% | -4.29% |
| sorted-map | +0.21% | -1.70% | -1.82% |
| Geometric mean across paired case medians | -3.96% | -6.77% | -2.83% |

The five object-only sorted-map regressions and mixed strconv samples remain
in these results. Independent full-suite confirmation uses the unchanged
`ed848ac5` downstream sources, frozen SDK 20261028 and original serial Wasm test
driver. All nine runs pass 8,384 tests with identical output. Official, parent
and combined median wall times are 18.600476, 210.673033 and 206.404817 seconds.
The three paired candidate changes are -1.94%, -2.04% and -2.09%. The paired
wall-ratio geometric mean changes from 11.326x to 11.097x official; the older
11.81x session is not this experiment's baseline. The large remaining total-time
gap is unresolved. Incremental hot gains are not summed to estimate that gap.
