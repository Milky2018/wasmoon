# MilkIR optimizer

This document describes the current implementation after ISS-459 and ISS-461.
Older e-graph/Cranelift comparison reports are historical analyses, not the
current pipeline specification.

## One authoritative expression graph

The Function DFG owns values, definitions and instructions. The optimizer does
not copy that graph into e-nodes, run equality saturation or extract a second
graph. An optimization session maintains dense constant/use indexes and
directional value aliases, scoped by dominance. A sibling block cannot reuse
an expression that exists only in another sibling.

O2 runs mandatory cleanup and scalar constant folding, then one dominator-order
walk that performs local rewrites and value numbering together. Cheap pure
value numbering is not disabled by whole-function size. Memory GVN uses its
own bounded analysis and effect/alias state; running out of memory-analysis
work does not turn off scalar simplification or invalidate already proven
prefix reuse. Alias/DCE and CFG cleanup run afterward, followed by sinking of
single-use materializations. O3 performs its checked loop transformations
before this acyclic walk, rather than running O2 twice.

## Handwritten direct dispatch

`opt_acyclic_rewrite.mbt` dispatches on the root opcode. Cohesive files implement
integer arithmetic, bitwise relations, comparisons, select, shifts,
reassociation, narrowing, floats and vectors. There is no rule schema, generated
matcher, bucket scan or saturation loop in the runtime optimizer.

Identity elimination and canonicalization update the root directly. Rules that
need helper instructions stage them transactionally. A candidate is committed
only if its IR complexity is strictly lower than the replaced expression;
rejection deletes the staged definitions. Constants/copies cost zero, integer
multiplication costs two, and other operations cost one. This is an algebraic
complexity model, not target latency. It prices scalar and vector multiplication
consistently. It does not promise an improvement on every target.

Rules rebuilding a child require single-use evidence. A shared child cannot be
counted as eliminated to justify new instructions. Constant-only staged integer
operations fold immediately. Rewrites are directional and local; the optimizer
does not enumerate every equivalent expression or guarantee a global optimum.

## Semantic boundaries

- Integer algebra is modular at the actual i32/i64 width. Shift and rotate
  amounts are masked at that width before combination. Narrowing a shift also
  proves that changing the operand width does not change count semantics.
- Scalar min/max and integer absolute value remain compare/select expressions.
  Bounds can be proven from those expressions without an optimizer-only opcode
  that must later be expanded. There is no scalar spaceship opcode.
- Vector splat folding uses the explicit lane width, including float bit
  patterns. Binary splat lifting checks identical integer lane types and use
  counts. Narrow signed/min/max/popcount/shift operations are not blindly
  replaced with their wider scalar counterparts.
- Floating arithmetic folds at its declared precision. NaN arithmetic remains
  at runtime; sign-only identities work on bits, preserving NaN payloads and
  signed zero. Nearest uses ties-to-even, and min/max distinguish positive and
  negative zero. No fast-math identities are assumed.
- Calls, loads, stores, traps and dialect operations retain their semantic
  effect contracts. No algebraic cancellation deletes a possibly trapping
  division or remainder. Constant division retains definedness checks.
- Target immediate/address/fused-instruction choices remain in native and
  target lowering. Algebraic equivalence alone does not justify expanding a
  multiply into several instructions or balancing a tree into longer live
  ranges.

## Migration and verification

The [complete legacy rule ledger](milkir-rewrite-inventory.md) classifies all
276 registered names, including invalid, unlowerable, equal-cost and
target-owned rules. A migrated row means the valid and profitable cases are
covered, not that unsafe legacy preconditions have been retained.

Tests combine exact optimized-IR assertions, a straight-line evaluator over
original and optimized i32/i64 DFGs, and JIT/interpreter differential execution.
Boundary coverage includes integer extremes, masked counts, shared definitions,
mixed vector lanes, narrow-lane wrapping, NaN payloads, signed zero and rounding
ties. Run native tests with `VCODE_REGALLOC_VALIDATION=1`; ordinary passing tests
alone do not establish allocation-verifier coverage.

Performance evidence must use isolated cold caches and interleaved builds of
the baseline and candidate. Wasmtime comparisons must additionally disable
parallel compilation. A successful rule migration is not itself evidence that
all workloads became faster.
