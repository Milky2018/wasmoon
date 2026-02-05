# Wasmoon Optimizations vs Wasmtime/Cranelift: Detailed Alignment Report

This document compares Wasmoon’s optimization pipeline and backend policies with
Wasmtime’s Cranelift, with a focus on **optimization behavior**, **lowering /
instruction selection**, **register allocation**, and **ISA/ABI policy
abstraction**.

The goal is not to re-implement Cranelift wholesale, but to:

1) Understand where Wasmoon already matches Cranelift’s behavior,
2) Identify material semantic or performance gaps, and
3) Produce a concrete, Cranelift-aligned roadmap for closing those gaps.

> Terminology note: Cranelift uses “x64” to mean x86-64/amd64; this document uses
> **amd64** unless quoting Cranelift module names.

---

## Scope, Versions, and Reproducibility

This report is based on static inspection of the following repository states:

- **Wasmoon**
  - Repo: `/Users/zhengyu/Documents/projects/wasmoon`
  - Commit: `899239362567ce804c69a453e5d63522916a2d54`
  - Version (moon.mod.json): `0.3.0`
- **Wasmtime / Cranelift**
  - Repo: `/Users/zhengyu/Documents/projects/wasmtime/wasmtime`
  - Commit: `68a6afd4f925724fd359c13a27fac5a6163d12f4`
  - Cranelift sources rooted at: `wasmtime/cranelift/` and `wasmtime/cranelift/codegen/`

### In-scope

- Wasmoon IR (`ir/`) + IR optimization driver and passes
- Wasmoon lowering (`vcode/lower/`) and VCode-level peephole/LICM
- Wasmoon register allocation (`vcode/regalloc/`)
- Wasmoon ISA/ABI policy layer (`vcode/isa/`) and how it feeds regalloc + codegen
- Wasmoon emission (`vcode/emit/`) for AArch64 and amd64
- Cranelift equivalents in:
  - `cranelift/codegen/src/context.rs` (pipeline)
  - `cranelift/codegen/src/egraph.rs` (aegraph pass)
  - `cranelift/codegen/src/remove_constant_phis.rs` (constant-phi removal)
  - `cranelift/codegen/src/isa/*` (lowering + ABI policy)
  - `cranelift/regalloc2` usage and machine-env concepts (via codegen integration)

### Out-of-scope (explicitly)

- End-to-end runtime architecture (GC, WASI, interpreter) except where semantics
  constrain optimization legality.
- Wasmtime’s higher-level wasm translation / environment decisions outside the
  Cranelift backend.

---

## Executive Summary (Key Findings)

### What’s already aligned (high value)

- **SSA + block parameters**: Wasmoon IR uses block parameters for phi-like
  merges, matching Cranelift’s conceptual approach.
- **Mandatory O0 cleanups**: Wasmoon keeps a small “must-run” cleanup set even
  at O0 (`DCE + block-param cleanup`), consistent with Cranelift’s philosophy
  that some canonicalization is required for downstream robustness.
- **Backtracking regalloc**: Wasmoon’s allocator is Ion-style/backtracking,
  conceptually similar to Cranelift’s “backtracking” option in regalloc2.
- **ISA/ABI policy abstraction direction**: Wasmoon’s `vcode/isa/` is a
  Cranelift-style layer that centralizes machine-env and clobber policy.

### Where the largest gaps are (optimization quality & predictability)

- **E-graph scope + integration**: Wasmoon’s egraph engine supports saturation,
  but the current IR integration is **per-basic-block** and intentionally
  **one-pass** (`saturate_indexed(..., 1)`), which is already a
  Cranelift-inspired “directional simplification” choice. Cranelift’s
  `EgraphPass` is **function-wide**, skeleton-driven, bounded by strict limits
  (`MATCHES_LIMIT`, `ECLASS_ENODE_LIMIT`), and integrates alias analysis +
  loop-aware elaboration (LICM-style placement).
- **Alias analysis and load optimization**: Wasmoon’s load CSE/GVN uses
  conservative invalidation; Cranelift uses alias analysis and LastStores to
  enable store-to-load forwarding and more aggressive elimination.
- **Lowering / isel completeness on amd64**: Cranelift’s x64 lowering is deeply
  ISLE-driven and aggressively uses addressing modes, constant pools, and
  ISA-feature gating. Wasmoon’s amd64 backend is intentionally incremental and,
  as of the referenced commit, the CLI conservatively disables JIT on amd64 for
  correctness.

### Recommendation (roadmap framing)

To “align with Cranelift” efficiently, prioritize:

1) **Bounded, predictable mid-end**: introduce match/eclass limits and a
   scoped GVN strategy (Cranelift-style) for Wasmoon’s egraph, plus optional
   alias analysis hooks for memory optimizations.
2) **Lowering parity for hot ops**: use Cranelift x64/aarch64 lowerings as the
   reference for instruction selection patterns (addrmode sinking, comparisons,
   conversion sequences, SIMD).
3) **Regalloc policy correctness**: continue pushing ISA policy behind the ISA
   layer; ensure verifier-level invariants (SSA, constraint satisfaction) match
   Cranelift’s expectations.

---

## Terminology: IR Layers in Both Systems

### Wasmoon

- **IR** (`ir/`): SSA-form IR with block parameters; instructions stored inside
  blocks (`ir/ir.mbt`).
- **VCode** (`vcode/instr/` + `vcode/lower/`): lower-level, machine-near IR used
  by regalloc + emitter. Note that VCode contains ISA-specific opcodes for
  AArch64 (e.g., shifted operands, MADD/MSUB) and amd64 sequences.

### Cranelift

- **CLIF IR**: SSA IR with `DataFlowGraph` + separate `Layout` ordering.
- **MachInst / VCode**: backend “machinst” IR used for isel, scheduling, and
  regalloc2 input (“vcode” in regalloc2 terminology is distinct from Wasmoon’s
  VCode).

This means “VCode” is a naming collision; when referencing Cranelift “VCode”,
this report will say **regalloc2 vcode**.

---

## 1) End-to-End Pipeline Map (Phase-by-Phase)

### Wasmoon pipeline (simplified)

1. Wasm → Wasmoon IR
   - Translators: `ir/translator*.mbt`
2. IR optimization (levels O0–O3)
   - Driver: `ir/opt_driver.mbt`
   - Pass sets: `ir/opt_passes_*.mbt`, `ir/egraph/*`
3. Lowering IR → VCode
   - `vcode/lower/lower*.mbt` + `vcode/lower/patterns.mbt`
4. VCode peephole / LICM (selected transforms)
   - `vcode/lower/peephole*.mbt`
5. Register allocation
   - `vcode/regalloc/*`
6. Emission (AArch64 / amd64)
   - `vcode/emit/*`

### Cranelift pipeline (simplified)

1. Wasm frontend → CLIF IR (not detailed here)
2. `Context::optimize()` (up to pre-isel)
   - `cranelift/codegen/src/context.rs`
   - includes nan canonicalization (optional), legalization, CFG/domtree,
     unreachable elimination, constant-phi removal, alias resolution,
     and egraph pass.
3. ISLE lowering (CLIF → MachInst)
   - `cranelift/codegen/src/isa/<isa>/{lower.isle,inst.isle}`
4. MachInst lowering + regalloc2 + late opts
   - `cranelift/codegen/src/machinst/*`
5. Emission + unwind info, relocations, etc.

### Structural difference that matters

Cranelift’s mid-end optimizations are largely consolidated into a single
bounded pass (`EgraphPass`) after legalization + canonical CFG cleanup; Wasmoon
uses an iterative driver that repeatedly runs multiple passes (including a
saturating egraph optimizer).

This affects:

- **Predictability**: Cranelift has hard limits; Wasmoon can, in principle,
  explode if a ruleset interacts badly with a large function.
- **Opportunity**: Cranelift can combine GVN + alias analysis + LICM decisions
  within the same elaboration framework; Wasmoon does these with separate passes
  and coarser invalidation.

---

## 2) Optimization Levels and Scheduling

### Wasmoon: O0–O3 (explicit levels)

Defined in `ir/opt_driver.mbt`:

- **O0**: not “no work”; runs a mandatory cleanup set:
  - `eliminate_dead_code`
  - block-param cleanups (`eliminate_constant_block_params`,
    `eliminate_dead_block_params`)
- **O1/O2/O3**: iterative fixed point (bounded by `max_iterations = 100`) that
  runs:
  - egraph rewrite (`optimize_function`),
  - classic scalar opts (constant fold, copy-prop, CSE, GVN, DCE),
  - CFG opts (branch simplify, unreachable, block merge, jump threading) at O2+,
  - post-fixed-point IR-level rematerialization + DCE cleanup.

**Alignment with Cranelift**: the “mandatory cleanup even at O0” approach is
consistent with Cranelift’s view that downstream codegen benefits greatly from
canonicalization and dead-phi cleanup.

### Cranelift: settings-driven opt levels

Cranelift’s `opt_level` is a flag (`none`, `speed`, `speed_and_size`) configured
via `cranelift/codegen/src/settings.rs`, used in `Context::optimize()`:

- Always:
  - optional NaN canonicalization,
  - legalization,
  - CFG + domtree computation,
  - unreachable elimination,
  - constant-phi removal,
  - alias resolution (`dfg.resolve_all_aliases()`).
- Only when `opt_level != None`:
  - `EgraphPass` (bounded aegraph + GVN + rewrite rules + store-to-load + LICM
    during elaboration).

**Key difference**: Cranelift does *one* egraph pass (bounded) rather than a
fixed-point loop of multiple passes.

### Recommendation: scheduling alignment points

1) Maintain the O0 cleanup set (good and Cranelift-aligned).
2) Make Wasmoon’s egraph predictable:
   - introduce `MATCHES_LIMIT` and `ECLASS_ENODE_LIMIT` analogues.
3) Consider refactoring the O2/O3 driver from “global fixed point” to:
   - a bounded “canonicalize + egraph + cleanup” pipeline,
   - with smaller local iterations inside passes where needed.

---

## 3) IR Representation and Consequences for Optimization

### Wasmoon IR (`ir/ir.mbt`)

Notable traits:

- Instructions are stored directly in blocks (`Block.instructions : Array[Inst]`).
- An IR instruction has:
  - `results : Array[Value]`,
  - `opcode : Opcode`,
  - `operands : Array[Value]`.
- Wasmoon has a `Copy` opcode (both in IR and in VCode-level mechanisms), and
  copy propagation is an explicit optimization.
- CSE/GVN use `Hash`/`Eq` on `Inst` keyed by opcode + operand value IDs.

### Cranelift CLIF IR (conceptual)

Notable traits (see `cranelift/codegen/src/ir/dfg.rs` and `context.rs` usage):

- `DataFlowGraph` stores `InstructionData` in an arena (`PrimaryMap`).
- Instruction ordering is separate (`Layout`).
- Value arguments use a shared `ValueListPool`.
- **No copy instructions**: Cranelift relies on value aliasing (`resolve_aliases`)
  instead of explicit Copy ops.

### Impact on optimization design

Cranelift’s “no-copy IR + alias resolution” changes how mid-end passes reason
about equivalences and how cheaply they can unify values:

- Wasmoon’s passes must consider explicit Copy instructions and may need to
  chase through them (or rely on earlier copy-prop).
- Cranelift’s `resolve_aliases` is a stable canonicalization step used in the
  pipeline (`Context::optimize()`), enabling later passes to treat the graph as
  “copy-free”.

**Actionable alignment**:

- Treat “resolve copy/aliases to canonical values” as a first-class step in
  Wasmoon’s pipeline (similar to Cranelift’s `resolve_all_aliases()`), rather
  than as a best-effort byproduct of copy-prop.

---

## 4) Mid-End Optimizations: Pass-by-Pass Comparison

This section maps key Wasmoon passes to Cranelift’s mid-end behavior, with
notes on differences and the practical implications.

### Quick mapping table (Wasmoon → Cranelift)

Cranelift does not have a 1:1 mapping of “small passes” like Wasmoon; many of
the equivalent transforms happen inside a single bounded `EgraphPass` after
legalization. The table below is meant as an orientation aid.

| Wasmoon pass / stage (approx driver order) | Where | Closest Cranelift analogue | Practical delta |
|---|---|---|---|
| Per-block egraph rewrite (`optimize_function`) | `ir/egraph_builder.mbt` | `EgraphPass` skeleton simplification + ISLE mid-end rules | Wasmoon is block-scoped; Cranelift is function-scoped and skeleton-driven. |
| Constant folding | `ir/opt_passes_basic.mbt` | ISLE rules + `EgraphPass` | Similar intent; Cranelift relies more on ISLE rewrite coverage. |
| Redundant `LoadMemBase` elimination | `ir/opt_passes_cse_gvn.mbt` | No direct analogue; similar concerns around pinned-reg / vmctx reads | Wasmoon has a dedicated conservative pass; Cranelift typically models such reads explicitly. |
| Copy propagation | `ir/opt_passes_basic.mbt` | `dfg.resolve_all_aliases()` (post-phi-removal canonicalization) | Wasmoon has explicit `Copy`; Cranelift uses value aliases. |
| Global CSE | `ir/opt_passes_cse_gvn.mbt` | `EgraphPass` GVN map (scoped by domtree) | Wasmoon is a standalone domtree walk; Cranelift integrates GVN into aegraph. |
| Global GVN + load CSE | `ir/opt_passes_cse_gvn.mbt` | `EgraphPass` GVN + `AliasAnalysis`/`LastStores` | Wasmoon uses conservative invalidation; Cranelift uses alias analysis and forwarding. |
| DCE | `ir/opt_passes_basic.mbt` | aegraph extraction + cleanup | Wasmoon is explicit/iterative; Cranelift is largely implicit during extraction/elaboration. |
| Constant block-param elimination | `ir/opt_cfg.mbt` | `remove_constant_phis.rs` | Very similar lattice approach; Cranelift benefits from copy-free IR. |
| Dead block-param elimination | `ir/opt_cfg.mbt` | (No dedicated pass) | Wasmoon’s explicit pass is useful due to SSA conversion of locals. |
| Branch simplification | `ir/opt_cfg.mbt` | CFG cleanup + unreachable elimination | Cranelift has fewer explicit CFG passes here; relies on canonicalization + extraction. |
| Unreachable elimination | `ir/opt_cfg.mbt` | `unreachable_code::eliminate_unreachable_code` | Broadly aligned. |
| Block merge / jump threading | `ir/opt_cfg.mbt` | (No direct analogue in `Context::optimize`) | Wasmoon is more aggressive at CFG shaping pre-isel. |
| Rematerialization (post fixed-point) | `ir/opt_passes_remat.mbt` | `opts/remat.isle` + `egraph/elaborate.rs::maybe_remat_arg` | Strong alignment: same goal (shrink live ranges) and similar policy (non-recursive). |
| Loop opts (O3) | `ir/opt_loops.mbt` | Loop-aware elaboration (LICM-like) | Cranelift does not do classic loop-unroll in codegen; Wasmoon does. |

### 4.1 Dead code elimination (DCE)

- Wasmoon:
  - `ir/opt_passes_basic.mbt` (and used in O0 and post-remat cleanup).
  - Repeatedly applied inside fixed-point loops.
- Cranelift:
  - DCE is largely achieved via the aegraph extraction phase (elaborate only
    needed skeleton nodes) and by removing unused nodes during/after egraph.

**Difference**:

- Wasmoon’s DCE is explicit and iterative; Cranelift’s DCE is implicit in
  aegraph extraction (plus other canonical passes).

**Recommendation**:

- Keep Wasmoon’s explicit DCE (valuable), but consider making it a smaller
  number of invocations (e.g., after egraph + after remat) once the egraph is
  bounded.

### 4.2 Constant-phi / block-param cleanup

- Wasmoon:
  - `eliminate_constant_block_params` + `eliminate_dead_block_params` (O0+).
- Cranelift:
  - `remove_constant_phis` (`cranelift/codegen/src/remove_constant_phis.rs`)
    uses a dataflow solver over a lattice `{None, One(v), Many}` and edits the
    CFG to remove redundant formals/actuals and insert renames.

**Difference**:

- Cranelift’s constant-phi removal is a dedicated, structured analysis that is
  known to pay for itself by reducing downstream isel/regalloc cost.
- Wasmoon’s approach is effective but generally simpler and depends more on the
  shape of the IR and existing copy-prop.

**Alignment opportunity**:

- If Wasmoon observes heavy “phi traffic” or pathological block-param growth
  (common in large unoptimized wasm), adopting a Cranelift-like lattice solver
  can make this pass both faster and more effective.

### 4.3 CSE / GVN (pure expressions)

- Wasmoon:
  - `eliminate_common_subexpressions` (local)
  - `eliminate_common_subexpressions_global` (domtree-based)
  - `gvn_global` and `gvn` (includes conservative load CSE; see below)
- Cranelift:
  - Aegraph pass uses a **scoped GVN map** keyed by `(Type, InstructionData)`,
    visited in domtree order, with bounded rewriting.

**Difference**:

- Cranelift’s GVN map is scoped by dominance traversal and integrates with
  rewrite application, ensuring value availability and minimizing redundant work.
- Wasmoon’s global CSE uses a DFS of the dominator tree with an environment,
  but does not integrate rewrites and does not have hard bounds on rewrite
  exploration.

**Recommendation**:

- Reuse the “scoped map on domtree traversal” pattern more broadly:
  - unify global CSE and GVN into a single scoped-environment pass,
  - then layer bounded egraph rewrites on top (or integrate as Cranelift does).

### 4.4 Load CSE and alias analysis

- Wasmoon:
  - `gvn` includes memory read/write classification plus conservative
    invalidation (`may_write_memory`, `reads_memory`).
  - Explicitly avoids CSE for potentially-trapping ops (div/rem, float-to-int).
- Cranelift:
  - Aegraph pass uses alias analysis (`AliasAnalysis`, `LastStores`) to do:
    - store-to-load forwarding,
    - load elimination in more cases than simple invalidation allows,
    - while still being bounded and robust.

**Difference**:

- Wasmoon’s approach is safe but leaves performance on the table in memory-heavy
  code: any “may write” clears the world.
- Cranelift’s alias analysis is significantly more precise and enables
  optimizations such as forwarding and dedup across more control-flow shapes.

**Recommendation**:

- Keep the conservative invalidation logic as a baseline, but add an optional
  alias-analysis layer (even a lightweight one) to:
  - avoid invalidating non-aliasing loads,
  - enable limited store-to-load forwarding.

### 4.5 NaN canonicalization and float semantics

- Cranelift:
  - Optional `enable_nan_canonicalization`, invoked before legalization.
- Wasmoon:
  - Does not have a single, explicit “nan canonicalization” pass at IR level.
  - Instead, float semantics are enforced in lowering/emission sequences.

**Difference**:

- Cranelift can canonicalize NaNs early to simplify later transforms and reduce
  the need for complex “ordered/unordered” handling in some patterns.
- Wasmoon maintains NaN-correctness mainly through lowering sequences, which
  is more local but often requires more instruction-level care.

**Recommendation**:

- Decide explicitly whether to add a canonicalization knob:
  - If yes, add an IR pass similar in intent to Cranelift’s option.
  - If no, document the invariant that lowering must preserve full wasm NaN
    semantics and avoid transforms that assume canonical NaNs.

### 4.6 Rematerialization (live-range shrinking)

Wasmoon and Cranelift are unusually well-aligned here: both treat
rematerialization as a post-optimization placement choice to reduce register
pressure.

- Wasmoon:
  - `rematerialize_across_blocks` in `ir/opt_passes_remat.mbt`
  - Selects candidates similar to Cranelift:
    - `iconst/fconst`, `bnot`, and ALU-with-imm (`iadd/isub/band/bor/bxor` with
      one constant operand).
  - Clones the defining instruction into each use block **once per block**,
    inserting it immediately before the first use (cached for later uses in the
    block).
  - Intentionally **non-recursive** (does not remat operands of rematted defs).
- Cranelift:
  - Candidate selection: `cranelift/codegen/src/opts/remat.isle`
  - Placement during elaboration: `cranelift/codegen/src/egraph/elaborate.rs`
    (`maybe_remat_arg`)

**Key delta**:

- Cranelift’s remat interacts with `available_block` and loop-aware elaboration
  decisions inside `EgraphPass`; Wasmoon runs a dedicated IR pass after reaching
  a fixed point. The end effect (shrinking cross-block live ranges for cheap
  values) is similar, but Cranelift can make placement decisions in a more
  unified way.

---

## 5) E-graph Optimization Frameworks: Wasmoon EGraph vs Cranelift Aegraph

This is the largest “optimizer design” difference between the two projects.
Both systems use an egraph-like representation (equivalence classes + multiple
representations) plus cost-based choice, but **they integrate it at different
scopes** and with different boundedness guarantees.

### 5.1 Wasmoon: egraph engine (`ir/egraph/egraph.mbt`)

Wasmoon’s egraph implementation is a classic union-find egraph with a few
Cranelift-inspired mechanics:

- **Core data structures**
  - `uf : UnionFind` + `classes : Map[Int, EClass]`
  - `hashcons : Map[ENode, EClassId]` for deduplication
  - `opcode_index : Map[EOpcodeTag, HashSet[Int]]` for opcode-indexed rule
    application
  - `uses : Map[Int, HashSet[Int]]` parent tracking (used during rebuild)
  - side tables: `type_map` (bit widths) and `remat_set`
- **Canonicalization**
  - `canonicalize()` normalizes commutative binary operands:
    - prefer constants on the RHS,
    - otherwise sort by canonical class id for determinism.
- **Directed unioning + “subsume”**
  - `merge(a, b)` forces `b` to remain the root via `union_keep(b, a)`.
  - `subsume(a, b)` redirects `a` to `b` without merging nodes, used to avoid
    infinite loops in associativity/commutativity rules.
  - This maps closely to Cranelift’s use of `subsume` as a rewrite primitive.
- **Rebuild / congruence closure**
  - `rebuild()` re-canonicalizes and re-hashconses nodes to discover new
    equivalences after unions, then re-roots `opcode_index`, `uses`, `type_map`,
    and `remat_set`.
- **Extraction / cost model**
  - `node_cost()` is a simple target-independent heuristic.
  - `extract()` recursively chooses the lowest-cost node per e-class with
    memoization, cycle detection, and pruning.

**Bounding policy (engine-level)**:

- `saturate_indexed(ruleset, max_iterations)` provides an iteration budget.
- `rewrite_to_fixpoint()` uses a *size-derived* budget
  (`(num_classes + num_nodes + 1) * 2`).
- There is **no** explicit equivalent to Cranelift’s `MATCHES_LIMIT` or
  `ECLASS_ENODE_LIMIT` in the engine today; the practical bound comes from how
  the egraph is used in IR optimization (next section).

### 5.2 Wasmoon: current IR integration (`ir/egraph_builder.mbt`)

Wasmoon currently uses the egraph **locally within each basic block**:

- `optimize_function()` builds an `EGraphBuilder` per block, registers in-block
  SSA defs, and converts a subset of IR opcodes into e-nodes (others become
  `Var(_)` leaves).
- The ruleset is a cached global singleton:
  - `EGraphBuilder::new()` uses `@egraph.get_global_ruleset()`.
  - Rules are indexed by opcode tags in `ir/egraph/rules_all.mbt`.
- Optimization is intentionally **one-pass**:
  - `EGraphBuilder::optimize()` calls `egraph.saturate_indexed(ruleset, 1)` with
    an explicit comment: “Cranelift-style aegraph”.
- Results are applied in-place by:
  - rewriting operands to per-block representatives that are type-correct and
    defined early enough to dominate later uses in the same block, and
  - replacing certain opcodes with constants where possible.

**Implications vs Cranelift**:

- Scope is *per-block*, so the egraph cannot directly perform cross-block GVN,
  skeleton-driven extraction, or LICM-like placement.
- The opcode subset currently includes some operations that can trap (e.g.
  `Sdiv/Udiv/Srem/Urem`, float-to-int conversions), which means rewrite rules
  must preserve wasm trap semantics. Cranelift avoids this by defining
  “pure-for-egraph” as excluding `can_trap()` ops (with a narrow exception for
  readonly+notrap+movable loads).

### 5.3 Cranelift aegraph (`cranelift/codegen/src/egraph.rs`)

Key traits:

- **Single-pass directional** optimization over a skeleton:
  - removes non-skeleton nodes from layout,
  - performs GVN + bounded rule application to create Union nodes,
  - extracts best representation (cost-based),
  - elaborates in a dominance/loop-aware manner (includes LICM-like placement).
- **Cost model** (selection/extraction):
  - `cranelift/codegen/src/egraph/cost.rs` uses a saturating `Cost(u32)` with
    a depth tie-break and loop-nest scaling to bias extraction and placement
    toward hoisting expensive ops out of loops.
- Hard bounds:
  - `MATCHES_LIMIT: usize = 5`
  - `ECLASS_ENODE_LIMIT: usize = 5`

Practical consequences:

- Highly predictable compile times.
- Still captures many of the benefits of equality saturation, but within bounds.

### 5.4 Concrete alignment opportunities (decision points)

If the goal is “Cranelift-like behavior”, the most important deltas are:

| Topic | Wasmoon today | Cranelift today | Alignment options |
|---|---|---|---|
| **Scope** | Per-block egraph rewrite + separate global passes (GVN/LICM) | Function-wide skeleton pass | Keep per-block (simpler) but don’t expect skeleton-grade wins, or evolve toward a CFG-scoped aegraph-like pass. |
| **Bounding** | One-pass rewrite per block; no explicit per-eclass caps | `MATCHES_LIMIT` + `ECLASS_ENODE_LIMIT` | Add explicit caps to rule application / insertion even if keeping one-pass. |
| **Purity / traps** | Some can-trap ops participate | `is_pure_for_egraph` excludes `can_trap()` | Define a Cranelift-like “egraph-safe” opcode set; treat trapping ops as skeleton-only. |
| **Cost model** | Simple `Int` `node_cost`; not loop-aware | Saturating `Cost`, loop-level scaling, depth tie-break | Import loop-aware scaling + depth tie-break heuristics, and make the “unit” closer to x64/aarch64 costs. |
| **Placement** | In-place rewrite only | Scoped elaboration with LICM-like placement | Keep IR-level `rematerialize_across_blocks` as the first step; later consider aegraph-like placement if CFG-scoped egraph is added. |

---

## 6) Lowering / Instruction Selection (IR → Machine-Near IR)

Cranelift’s defining strength is ISLE-driven instruction selection that is both
**semantic** (correctness-first) and **mechanical** (priorities, feature gates,
addressing modes).

Wasmoon’s lowering is a mix of:

- dedicated lowering modules (`vcode/lower/lower_*.mbt`),
- a pattern system (`vcode/lower/patterns.mbt`),
- plus some handwritten fusions (e.g. in `lower_numeric.mbt`).

### 6.1 Addressing modes and “sinking” memory ops

Cranelift x64 lowering (see `cranelift/codegen/src/isa/x64/lower.isle`) has
explicit higher-priority rules that “sink” loads into arithmetic ops when
possible (`sinkable_load`) and uses `lea` patterns for add trees.

Wasmoon lowering performs some fusions (e.g., AArch64 shifted operand patterns,
MADD/MSUB/MNEG) but generally does not have the same breadth of addressing-mode
selection logic on amd64.

**Recommendation**:

- For amd64, adopt Cranelift’s approach as the reference:
  - define “sinkable” loads (trusted addressing, no traps, alignment, etc),
  - lower add/mul trees to `lea`/addrmodes where legal,
  - preserve wasm trap semantics (bounds checks) by only sinking when safe.

### 6.2 Constant materialization strategy

- Cranelift:
  - XMM constants are generally loaded from a constant pool (`x64_xmm_load_const`
    in `inst.isle`), which becomes a memory load from a synthetic amode.
- Wasmoon:
  - The amd64 backend currently favors “no constant pool” sequences for V128
    materialization and masks (e.g., XOR + PINSRQ), trading code size for
    simplicity.

**Recommendation**:

- Introduce a small constant pool abstraction for amd64 in Wasmoon emission,
  mirroring Cranelift’s vcode constant mechanism:
  - reduce instruction count for frequent masks,
  - reduce register pressure due to multi-step constant build,
  - enable more aggressive peepholes and remat choices.

### 6.3 Trap semantics and “optimization legality”

Cranelift and Wasmoon both treat potentially-trapping ops carefully:

- Wasmoon explicitly excludes div/rem and float-to-int conversions from GVN CSE
  candidates.
- Cranelift’s legalization, verifier, and rewrite rules are designed to avoid
  changing trap behavior; trap ops are explicit in the IR and lowering.

**Key alignment point**:

Any Wasmoon optimization that changes:

- whether a trap occurs,
- which trap occurs,
- or the relative order of side effects and traps,

must be guarded or restructured to match wasm semantics.

---

## 7) Late Optimization: Peephole and LICM

### Wasmoon VCode peepholes / LICM

Wasmoon performs some late transforms on VCode before regalloc, including a
simple LICM (`vcode/lower/peephole_licm.mbt`) that:

- detects natural loops via dominators/backedges,
- requires a unique outside predecessor to act as a preheader,
- hoists:
  - `LoadConst` (with heuristics to avoid pressure),
  - limited invariant loads from vmctx-derived data.

### Cranelift

Cranelift’s aegraph elaboration has a built-in LICM-like placement strategy:

- values are elaborated at chosen points based on dominance and loop analysis,
  rather than via a separate dedicated “VCode LICM” pass.

**Recommendation**:

- Keep the current VCode LICM for Wasmoon (it’s valuable and already bounded),
  but consider migrating invariant hoisting earlier:
  - into IR-level egraph elaboration (Cranelift-like),
  - or into a unified “extraction + placement” phase if Wasmoon adopts a more
    aegraph-style mid-end in the future.

---

## 8) Register Allocation and Machine Environment

### Wasmoon regalloc (`vcode/regalloc/*`)

Wasmoon’s allocator is Ion-style/backtracking with:

- explicit liveness / live-range construction,
- bundling and copy coalescing,
- splitting and spilling,
- an ISA-dependent machine environment (`vcode/isa/isa.mbt` → `MachineEnv`).

### Cranelift regalloc2

Cranelift uses regalloc2, with:

- algorithm selection (default: backtracking),
- optional regalloc checker/verifier,
- machine env provided by ISA backend (`TargetIsa::machine_env()`).

### Alignment deltas

1) **Verification**:
   - Cranelift can enable verifier and regalloc checker in settings.
   - Wasmoon has internal wbtests and some checker logic; consider making
     “regalloc validation” an explicit optional gate.
2) **Operand constraints**:
   - regalloc2 supports expressive constraints; Wasmoon has constraints but has
     historically seen issues when ISA-specific assumptions leaked (now improved
     via ISA layer).
3) **Pinned registers**:
   - Wasmoon still has a set of pinned-register constants in `vcode/abi/abi.mbt`
     for vmctx/memory/table/scratch roles.
   - Cranelift has a “pinned-reg” option but generally prefers to describe
     policy via ABI + lowering constraints rather than global constants.

**Recommendation**:

- Continue migrating pinned constants into ISA “roles”:
  - exactly one source of truth per role, per ISA,
  - consistent with Cranelift’s ABI policy design.

---

## 9) Correctness Edge Cases That Affect Optimization

Certain semantic corner cases are “optimization landmines” and require explicit
alignment with Cranelift’s sequences:

1) **Signed div/rem overflow** (`INT_MIN / -1`, `INT_MIN % -1`)
   - Must not trap (for remainder) and must trap correctly (for division) per
     wasm semantics.
2) **NaN behavior in comparisons and min/max**
   - Ordered/unordered compare handling must match wasm rules.
3) **Float-to-int conversions**
   - Trapping vs saturating variants must match wasm spec; Cranelift’s lowering
     sequences are a good reference.
4) **SIMD semantics (including relaxed-simd)**
   - Many patterns rely on specific instruction sequences and ISA-feature
     gating (SSE2/SSSE3/SSE4.1, etc) to match semantics.

For all of these, treat Cranelift’s lowering rules (`inst.isle` / `lower.isle`)
as the canonical reference for amd64 and AArch64 sequence structure.

---

## 10) Measurement and Validation Methodology (Recommended)

To compare optimizers meaningfully, measure:

- **Compile-time**
  - IR instruction count before/after opts
  - egraph nodes / classes / rewrite counts
  - time per pass (basic timing hooks)
- **Code quality**
  - VCode instruction count pre/post regalloc
  - spills/reloads counts
  - final machine-code size
- **Correctness gates**
  - `python3 scripts/run_all_wast.py --dir spec --rec`
  - targeted “JIT vs interp” differential tests where JIT is enabled

When reporting results, record:

- Wasmoon commit hash,
- Cranelift/wasmtime commit hash,
- target ISA (AArch64 vs amd64),
- opt level and any feature flags.

---

## 11) Gap Analysis and Prioritized Alignment Actions

This section is a concrete “what to do next” list, ordered by expected impact
and alignment value.

### P0: Predictability + correctness invariants

1) **Bound Wasmoon’s egraph**
   - Add hard limits analogous to Cranelift’s `MATCHES_LIMIT` and
     `ECLASS_ENODE_LIMIT`.
2) **Make alias/copy canonicalization explicit**
   - Add a dedicated “resolve aliases” step (copy chasing) early in the IR
     pipeline.
3) **Regalloc validation gate**
   - Add an optional verifier/checker mode similar to Cranelift settings.

### P1: Code quality improvements (Cranelift-derived)

1) **Addressing mode selection / load sinking (amd64 first)**
   - Implement “sinkable_load” rules and `lea` patterns similar to Cranelift.
2) **Introduce amd64 constant pools**
   - Mirror Cranelift `VCodeConstant` approach to reduce mask/materialization
     sequences.
3) **Unify lowering patterns**
   - Reduce duplication between `lower_numeric` handwritten fusions and
     `vcode/lower/patterns.mbt`; choose a single mechanism with priorities.

### P2: Deeper mid-end alignment

1) **Directional egraph / aegraph-like extraction**
   - Evolve from equality saturation to a bounded “union + extract + elaborate”
     approach over time.
2) **Alias analysis improvements**
   - Gradually add precision (field sensitivity, heap modeling) as needed for
     GC and wasm memory ops.

---

## Appendix A: Primary Code References (Wasmoon)

- IR and optimization:
  - `ir/ir.mbt`
  - `ir/opt_driver.mbt`
  - `ir/opt_passes_basic.mbt`
  - `ir/opt_passes_cse_gvn.mbt`
  - `ir/egraph/*`
- Lowering / patterns:
  - `vcode/lower/lower*.mbt`
  - `vcode/lower/patterns.mbt`
  - `vcode/lower/div_const.mbt`
  - `vcode/lower/peephole*.mbt`
- Regalloc:
  - `vcode/regalloc/*`
- ISA policy:
  - `vcode/isa/isa.mbt`
  - `vcode/isa/aarch64/*`
  - `vcode/isa/amd64/*`
- Emission:
  - `vcode/emit/*`

## Appendix B: Primary Code References (Cranelift)

- Pipeline and mid-end:
  - `cranelift/codegen/src/context.rs`
  - `cranelift/codegen/src/egraph.rs`
  - `cranelift/codegen/src/remove_constant_phis.rs`
  - `cranelift/codegen/src/opts/*` and generated ISLE rules
- ISA lowering / isel:
  - `cranelift/codegen/src/isa/x64/lower.isle`
  - `cranelift/codegen/src/isa/x64/inst.isle`
  - `cranelift/codegen/src/isa/aarch64/lower.isle`
  - `cranelift/codegen/src/isa/aarch64/inst.isle`
- ABI:
  - `cranelift/codegen/src/isa/x64/abi.rs`
  - `cranelift/codegen/src/isa/aarch64/abi.rs`
