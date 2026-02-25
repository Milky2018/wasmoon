# E-Graph Phase-J Execution Plan (Cranelift-Aligned)

## Goal

Align Wasmoon IR e-graph optimization behavior with Wasmtime/Cranelift’s aegraph pipeline to improve generated code quality and reduce unstable compile-time behavior, while preserving existing correctness guarantees.

## Scope

This plan covers IR-level optimization architecture and execution order, not new ISA features or parallel compilation.

## Cranelift References (must read before each milestone)

- `../wasmtime/wasmtime/cranelift/codegen/src/egraph.rs`
- `../wasmtime/wasmtime/cranelift/codegen/src/egraph/cost.rs`
- `../wasmtime/wasmtime/cranelift/codegen/src/egraph/elaborate.rs`
- `../wasmtime/wasmtime/cranelift/codegen/src/alias_analysis.rs`
- `../wasmtime/wasmtime/cranelift/codegen/src/inst_predicates.rs`

## Current Gap Snapshot

- Wasmoon currently runs e-graph optimization block-by-block (`ir/egraph_builder.mbt`), while Cranelift uses function-wide directional traversal over a side-effecting skeleton.
- Wasmoon rewrite/extract flow is simpler and does not yet match Cranelift’s scoped elaboration and LICM-like placement behavior.
- Alias-sensitive store/load forwarding and scoped GVN behavior are less tightly integrated than Cranelift.

## Milestones

### J0: Baseline and report format

- Lock benchmark/report format before behavior changes.
- Commands (same host, 5-run median):
  - `./install.sh`
  - `./wasmoon run examples/algorithms/aead_aegis128l.wasm`
  - `./wasmoon run examples/benchmark.wasm`
  - `wasmtime run examples/algorithms/aead_aegis128l.wasm`
  - `wasmtime run examples/benchmark.wasm`
- Save JSON + markdown summary under `docs/perf/baselines/<date>-phase-j/`.

### J1: Purity boundary and skeleton alignment

- Align Wasmoon “egraph-eligible” instruction boundary with Cranelift’s `is_pure_for_egraph` / `is_mergeable_for_egraph`.
- Keep can-trap and side-effecting ops out of rewrite domain, but represented in skeleton flow.
- Target files:
  - `ir/egraph_builder.mbt`
  - `ir/instruction.mbt`
  - `ir/optimize.mbt`

### J2: Function-scoped traversal and scoped GVN map

- Move from per-block independent optimize to function-scoped traversal with dominance-aware scoped maps.
- Model Cranelift’s `ScopedHashMap` behavior and depth placement decisions.
- Target files:
  - `ir/egraph_builder.mbt`
  - `ir/cfg.mbt`
  - `ir/optimizer_context.mbt` (if needed)

### J3: Alias-aware load/store optimization integration

- Add Cranelift-style alias state tracking around rewrite/GVN decisions.
- Preserve safety for trap and memory ordering semantics.
- Target files:
  - `ir/alias_analysis.mbt`
  - `ir/egraph_builder.mbt`
  - `ir/opt_passes_basic.mbt`

### J4: Cost model and extraction tie-breakers

- Align extraction objective with Cranelift `Cost` model shape:
  - Saturating arithmetic
  - opcode-cost first, depth tie-break behavior
  - stable deterministic tie-break for equal cost
- Target files:
  - `ir/egraph/egraph.mbt`
  - `ir/egraph_builder.mbt`

### J5: Scoped elaboration and placement

- Add Cranelift-like scoped elaboration from optimized values back to CFG positions.
- Introduce loop-aware placement/hoisting constraints and remat interaction points.
- Target files:
  - `ir/egraph_builder.mbt`
  - `ir/opt_passes_remat.mbt`
  - `ir/loop_analysis.mbt`

### J6: Validation and closeout

- Required gates:
  - `moon check --target native`
  - `moon test --target native`
  - `./install.sh`
  - `python3 scripts/run_all_wast.py --dir spec --rec`
- Perf acceptance for phase close:
  - `aead_aegis128l.wasm` and `benchmark.wasm` median runtime deltas documented vs Wasmtime.
  - No correctness regressions.

## Task Dependency Model

Execution order is strictly linear: `J0 -> J1 -> J2 -> J3 -> J4 -> J5 -> J6`.
Each task close note must include:

- commit hash
- exact Cranelift file references used
- gate results
- perf delta (if behavior/perf changed)
