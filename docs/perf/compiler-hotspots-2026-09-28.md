# Compiler hotspot investigation, 2026-09-28

## Conclusions

This is an investigation at Wasmoon `2b20de9f9bfa6c48cfeed5e5b26f5f50d9044cd0`,
not a new optimization or a claimed speedup. It extends
[the cold CLI study](cli-startup-2026-09-28.md). Production sources are unchanged.
The comparison source is Wasmtime v49.0.1 / Cranelift 0.136.1, commit
`46c23a87dac1465986a8ad53ba6a7ae49372857b`.

1. Allocator work is concentrated: the five most expensive functions account
   for 55–69% of allocation time in each diagnostic capture. Four inputs share
   a 5,018-opcode function shape; the other two share a closely related
   5,016-opcode shape. These six workloads are not six independent compiler
   stress patterns.
2. Bundle allocation is mostly probing/index work, not allocation/free calls.
   Across three CPU captures, the probe subtree occupies approximately 4.5–6.4%
   of compile-stack samples. Replacing the allocator wholesale is not supported
   by this evidence; measure the index operations and failed probes first.
3. Object destruction, scanning and allocation are substantial across the
   compiler as a whole. Three selected runtime leaf functions account for about
   29% of compile-stack samples. This does not identify a leak or justify
   weakening RC/ownership checks. Costs occur at many stage boundaries.
4. There are three concrete, bounded experiments worth trying next: reuse the
   acyclic pass's per-instruction prefix scratch; skip a duplicate owner scan
   when operand arrays are physically identical; compute jump-threading use
   counts only when a consumer exists. None has a measured saving yet.
5. Do not repeat the previously deferred CSR pointer-dependency experiment or
   import Cranelift's non-shadowing scoped map unchanged. Both have evidence or
   semantic constraints against doing so now.

## Evidence and limits

The function/pass timing and counters below are extracted from the candidate
(`after`) detailed captures retained by ISS-589. Each is one instrumented
capture, not a statistically precise time estimate. They describe the actual
CLI reachable-function selection. Timings from the earlier reference captures
are not relabeled as optimizer improvements.

A separate native sampling fixture uses the current release-generated C and
original native link command, adding debug symbols and frame pointers. Only the
fixture main body is repeated 400 times after one runtime initialization. The
compiler itself is unchanged. For `auth`, `xchacha20` and `generichash`, macOS
`sample` captures five seconds at a requested 1 ms interval. All 400 iterations
complete in each process, and each final complete artifact is byte-identical to
an ordinary one-shot compile of the same input. This verifies the final artifact,
not a separately retained hash for every intermediate iteration.

These are warm-process, repeated **eager public compile_module** profiles. They
include fresh per-compilation compiler state, but warm code/allocator pages;
they are not cold CLI latency measurements and do not estimate a speedup. Debug
information/frame pointers, compiler inlining, merged symbols, the finite sample
window, and different eager/CLI function selections limit attribution. No other
build, test or profiler overlaps a capture.

The derived stack summary computes each node's self samples as its inclusive
count minus its direct children, rejects negative results, and partitions those
self samples by ancestors. Selected inclusive subtrees may overlap and must not
be added. The raw sample reports, build/capture/derivation recipes, original and
modified generated-C hashes, machine-code excerpt, executable/input/artifact
hashes and extracted diagnostic data are retained in the
[compressed evidence](compiler-hotspots-2026-09-28.json.gz). No sampling helper is
installed as a project-style audit or CI acceptance gate.

## Concentration and work counts

| Workload | Compiled functions | Top five allocation-time share | Queue pops | Register probes | Occupied segments scanned | Evictions / splits |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| auth | 64 | 63.3% | 8488 | 61717 | 82247 | 162 / 206 |
| onetimeauth | 53 | 64.9% | 5915 | 36714 | 42263 | 128 / 172 |
| aead_chacha20poly1305 | 69 | 57.1% | 7705 | 46060 | 51227 | 148 / 196 |
| generichash | 53 | 68.5% | 7860 | 55406 | 84071 | 150 / 204 |
| aead_aegis128l | 63 | 54.9% | 9023 | 64057 | 69927 | 275 / 342 |
| xchacha20 | 91 | 66.0% | 19556 | 159986 | 194335 | 788 / 402 |

There are roughly 6–8 register probes per queue pop in these inputs. Occupied
segment visits are roughly 1.1–1.5 per probe, rather than evidence of an enormous
linear scan per attempt. These aggregate ratios do not reveal tail distributions;
we still need search depth, clobber-query hit rate, probe termination reasons and
scan lengths before changing the interval index.

The shared large function has Wasm indices `43/50/57/47` in
`auth/onetimeauth/aead_chacha20poly1305/generichash`, respectively. Each contains
5,018 printed instruction opcodes with exactly the same opcode-sequence digest,
and contributes about 4.8–4.9 ms of allocator time in those captures.
`aead_aegis128l:56` and `xchacha20:69` form the 5,016-opcode group.
The binaries do not carry function names; this is a structural comparison that
ignores immediates, **not proof of identical semantics or an identified libc
symbol**. The appropriate next corpus expansion is structurally different real
programs, retaining these existing controls, rather than counting more siblings
of the same benchmark as independent confirmation.

## CPU sampling

The following counts are restricted to stacks inside public compilation.
The three runtime leaf columns are mutually exclusive. The probe subtree is
inclusive and can contain runtime leaves, so it is not additive with them.

| Workload | Compile-stack samples | Object drop leaf | Object scan leaf | mi_malloc leaf | Probe subtree |
| --- | ---: | ---: | ---: | ---: | ---: |
| auth | 4137 | 759 (18.3%) | 165 (4.0%) | 270 (6.5%) | 196 (4.7%) |
| xchacha20 | 4202 | 753 (17.9%) | 200 (4.8%) | 295 (7.0%) | 267 (6.4%) |
| generichash | 4219 | 796 (18.9%) | 190 (4.5%) | 248 (5.9%) | 189 (4.5%) |

The combined selected runtime leaves account for 28.9–29.7% of compile-stack
samples, not all memory-management overhead. In contrast, inside the bundle
allocation category these same runtime leaves account for only about 6–8% of
that category's samples. High whole-compiler object-management cost therefore
does not imply that an object pool inside register probing is the right fix.

The most frequent nearby source-level callers of destruction include module
compilation, native target construction, target compilation and bundle-plan
construction. Inlining and shared runtime drop paths prevent assigning all of
these samples to one exact object type. We need allocation/lifetime attribution
before proposing arenas or deferred destruction; moving cleanup outside a timer
would not be an optimization of total command cost.

`RegisterAllocationIndex::seek` appears in 77/110/89 samples and
`RegisterClobberIndex::first_intersection` in 42/78/33 for
`auth/xchacha20/generichash`. They are nested within probing, not extra costs.
The current allocator already has an intrusive treap, cached ordered coordinates,
contiguous-owner skipping and short-scan fallbacks to search. See
[the interval index](../../modules/regalloc/register_allocations.mbt) and
[probe implementation](../../modules/regalloc/bundle_allocate.mbt).
A per-register cached search cursor would need invalidation across insertion,
eviction and bundle splitting; current priority order is not program order.
Do not assume a monotonic sweep or change inclusive endpoint rules.

## Acyclic optimizer

| Workload | Acyclic time / module time | Functions exhausting memory budget | Acyclic time in exhausted functions | Rewrite attempts | Committed helper instructions |
| --- | ---: | ---: | ---: | ---: | ---: |
| auth | 13.0% | 15/64 | 76.8% | 20874 | 0 |
| onetimeauth | 12.3% | 11/53 | 69.6% | 14240 | 0 |
| aead_chacha20poly1305 | 11.9% | 12/69 | 68.2% | 17663 | 0 |
| generichash | 12.1% | 12/53 | 75.8% | 17762 | 0 |
| aead_aegis128l | 13.2% | 17/63 | 78.5% | 24262 | 0 |
| xchacha20 | 12.1% | 24/91 | 84.1% | 46553 | 0 |

Budget exhaustion limits precise memory analysis, not all optimizer work.
Rewrites, cheap value numbering and side-effect invalidation continue beyond
that boundary. CFG/dominance setup is built before the acyclic timer and must
not be charged to the displayed acyclic duration. About 68–84% of acyclic time
occurs in exhausted functions; this does not establish that their setup work,
rather than rewriting or lookup, dominates.

### First experiment: reuse prefix scratch

[gvn.mbt: process_block](../../modules/milkir/optimize/internal/acyclic/gvn.mbt)
creates an empty `prefix` array for every source instruction, feeds it to
`rewrite_inst`, processes generated helpers, then canonicalizes the original
instruction's operands again. Generated C explicitly allocates the array wrapper
inside this loop, and optimized native assembly retains the 24-byte `mi_malloc`
call before `rewrite_inst`. The shared empty backing array does not eliminate
the wrapper allocation.

Across the six captures, 141,354 rewrites commit zero helper instructions.
This confirms frequent apparently empty scratch, **not zero speculative/rejected
candidates or a measured time saving**. A per-block scratch array, cleared per
instruction, can be tested without a long-lived global pool. Preserve helper
ordering, candidate rollback, and references until helper processing finishes.
Do not also remove the second canonicalization in the same experiment: helpers
can acquire aliases during GVN, making a second walk necessary.

Acceptance: count allocations separately, use ordinary full-compilation AB/BA,
verify complete artifact equality, exercise tests that actually create helpers,
and confirm total CLI time and peak memory. The CPU profile places acyclic work
alongside many other costs; this change cannot be assumed to close the overall
Wasmtime gap.

### Second experiment: duplicate owner scan

[ir.mbt](../../modules/milkir/ir.mbt), `Block::accepts_inst` at line 493, scans both
`inst.args` and `inst.operands`. The normal private constructor at line 682 assigns
both fields the same array. `reject_foreign_values` is visible as a self-frame in
93/66/66 of the three compile-stack captures, although these samples include
other callers and do not measure the duplicate scan alone.

The bounded candidate is: check `args` first; check `operands` only when the two
arrays are not physically identical; retain result/opcode checks and the same
first-error order. Do not remove ownership validation or rely on ID equality.
[Malformed-owner tests](../../modules/milkir/function_ownership_wbtest.mbt)
deliberately create separate arrays with foreign values in either one, and must
continue failing correctly. This is more precise than bypassing validation for
all internally constructed instructions.

### Third experiment: use-count scans without consumers

[thread_jumps](../../modules/milkir/optimize/cfg.mbt) at line 995 computes whole-
function use counts unconditionally at line 1001. Its only consumer is the
parameter predicate for blocks ending in `Jump` at lines 1008–1015. If no such
block has parameters, the scan is unnecessary. The existing block-index walk
could identify this condition without another full instruction traversal.

`compute_use_counts` occupies 89/80/85 self samples across the three captures,
but is shared by several passes. These counts are **not savings available to
jump threading**. First count how often the no-consumer condition occurs and
attribute callers. Keep session use-count initialization eager: its current
contract is a pre-rewrite snapshot, so deferring it until the first query could
observe already modified IR. Cross-pass caches would need explicit invalidation
and are a larger, unproven change.

### Later candidates and upstream lessons

- GVN currently looks up an instruction key, and insertion may perform another
  lookup followed by `set`, with keys hashing opcode identity, result types and
  operand IDs. Cranelift's [egraph entry path](https://github.com/bytecodealliance/wasmtime/blob/46c23a87dac1465986a8ad53ba6a7ae49372857b/cranelift/codegen/src/egraph/mod.rs#L511)
  provides a concrete comparison. Measure lookup/hash counts, empty-stack hits
  and table occupancy before replacing the representation.
- Cranelift's [scoped hash map](https://github.com/bytecodealliance/wasmtime/blob/46c23a87dac1465986a8ad53ba6a7ae49372857b/cranelift/codegen/src/scoped_hash_map.rs#L76)
  explicitly disallows shadowing. MilkIR must restore ancestor expressions after
  child scopes override memory versions or bounded reuse state. Its rollback
  records also avoid rehashing mutable instruction keys. A direct container swap
  is not valid, nor is ordinary union-find path compression without rollback.
- Cranelift's [alias-analysis worklist](https://github.com/bytecodealliance/wasmtime/blob/46c23a87dac1465986a8ad53ba6a7ae49372857b/cranelift/codegen/src/alias_analysis.rs#L869)
  seeds reverse postorder. MilkIR can investigate this scheduling lesson, but its
  full last-store fixed point is limited to small functions within the memory
  budget. The measured concentration favors other work first. Preserve the meet
  lattice and convergence for loops and irreducible CFGs.
- Contiguous pointer dependencies remain **deferred** under
  [ISS-587](../../issues/ISS-587.md): two prior rounds found inconsistent timing,
  only about 1% cumulative allocation savings and unchanged peak usage. No new
  result here overturns that decision. Restricting dependency edges to relevant
  transfer opcodes is a distinct hypothesis, still requiring worklist tests and
  measurements.

## Scope and next decision

Try the three bounded experiments independently, preserve rejected results,
and add structurally different real inputs before generalizing. For the
allocator, collect operation distributions before changing its search strategy.
No finding establishes a need to replace MilkIR, introduce a new egraph, weaken
public ownership safety or abandon MoonBit RC. The likely small savings should
be judged against the much larger remaining CLI gap, with complete compilation
and command lifetime included in every comparison.

Only analysis, issue tracking and evidence are changed in this commit. Existing
production test results are not presented as new tests of an optimization; the
new executable verification is the three diagnostic/ordinary artifact checks.

Repository gates were rerun after recording the analysis: `moon info`, `moon fmt`,
warning-denied native check, and all 2,586 native tests pass. These validate the
unchanged production tree, not any of the proposed future experiments.
