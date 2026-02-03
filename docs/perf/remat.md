# Rematerialization (Cranelift-Style) for Wasmoon IR

This document explains how we plan to adopt Cranelift’s rematerialization
approach in Wasmoon, and where it fits in our pipeline.

## Background: what Cranelift does

Cranelift has a concept of *rematerializable* IR values: values that are cheap
and side-effect-free to recompute at each use site to reduce register pressure.

Key references in `../wasmtime/wasmtime/cranelift`:

- `cranelift/codegen/src/opts/remat.isle`
  - Marks `iconst`, `f32const`, `f64const`, `bnot`, and ALU-with-imm patterns
    (e.g. `iadd`/`isub`/`band`/`bor`/`bxor` with an `iconst` operand) as *remat*.
- `cranelift/codegen/src/opts.rs`
  - The `remat(Value)` constructor records a `Value` in a `remat_values` set.
- `cranelift/codegen/src/egraph/elaborate.rs`
  - `maybe_remat_arg()` is the key behavior: when a remat value is used in a
    different block than where it was defined, Cranelift clones the defining
    instruction into the use-site block (cached per `(block, value)`), and
    rewrites that use to the cloned value. This shrinks live ranges across
    blocks. (Cranelift intentionally does not recurse into remat’s operands
    today; see the TODO in that file.)

Important: this is a *mid-end / IR-level* optimization. `regalloc2` (Ion) does
not “discover” remat by itself; it benefits from reduced live-range pressure
that the mid-end creates.

## Wasmoon today

Wasmoon IR is SSA and block-based:

- `ir/ir.mbt` defines `Function`, `Block`, `Inst`, `Value`, and terminators.
- The current e-graph optimizer (`ir/egraph/*`, `ir/egraph_builder.mbt`) is
  applied **per basic block** in `ir/egraph_builder.mbt::optimize_function`.
  This is great for algebraic simplifications and constant folding *inside a
  block*, but it cannot shrink live ranges that cross blocks.

There is already a remat-related ruleset (`ir/egraph/rules_remat.mbt`), but
because the e-graph optimization is block-local and extraction does not clone
instructions into other blocks, it does not implement Cranelift’s cross-block
remat effect.

## Mapping Cranelift remat to Wasmoon

We will implement a function-level IR pass that mirrors the *behavior* of
Cranelift’s `maybe_remat_arg()`:

### 1) Identify remat candidates (value-defining instructions)

We will use the same “cheap + pure” patterns as Cranelift’s `remat.isle`:

- Constants:
  - `Opcode::Iconst(_)`
  - `Opcode::Fconst(_)` (type distinguishes f32 vs f64 in `Value.ty`)
- Unary:
  - `Opcode::Bnot`
- Binary with an immediate/constant operand:
  - `Opcode::Iadd`, `Opcode::Isub`, `Opcode::Band`, `Opcode::Bor`,
    `Opcode::Bxor` when at least one operand is defined by `Iconst`.

We will *not* include loads, calls, or any instruction that can trap / has
side-effects.

### 2) Clone the defining instruction per use-block (non-recursive)

For each instruction operand `v` in block `B_use`:

- Find `v`’s defining instruction `inst_def` and block `B_def`.
- If `B_def != B_use` and `inst_def` is a remat-candidate:
  - Create (or reuse) a cached copy for `(B_use, v)`:
    - Clone `inst_def` into `B_use` once, immediately before the first use in
      that block.
    - The clone produces a fresh SSA `Value` id (via `Function::new_value`).
  - Rewrite this operand use from `v` to the cloned value.

This directly mirrors Cranelift’s cache `remat_copies: (Block, Value) -> Value`
and its “clone the defining inst” approach.

Why inserting before the first use is safe in SSA:

- In SSA, operands of `inst_def` dominate `inst_def`, and `inst_def` dominates
  the use. Therefore those operands also dominate the use block; if an operand
  is a blockparam, it is available throughout the block; otherwise it is
  defined in a dominating block and is available at the use site as well.

We will keep this **non-recursive** at first, matching Cranelift’s current
behavior (no remat-of-remat operands fixpoint).

### 3) Cleanup

After rewriting uses, many original defs may become dead. We should run DCE
after remat (or rely on the next existing DCE pass) to remove now-unused
instructions.

## Where this pass runs

Pipeline integration point (proposed):

1. `@ir.translate_function(...)`
2. `@ir.optimize_with_level(...)` (existing passes, plus a final remat+DCE step)
3. `@lower.lower_function(...)`
4. `@regalloc.allocate_registers_backtracking_output(...)`

This matches Cranelift’s intent: shrink live ranges *before* lowering/regalloc.

## Expected impact / measurement

Primary target: large crypto functions that currently spill heavily (e.g.
`examples/core_ed25519.wasm` function 36 showed hundreds of spill slots and a
very large stack frame in `./wasmoon explore ... --stage regalloc mc`).

We will track improvements by:

- spill slots count and inserted loads/stores in the regalloc summary
- stack frame size / stack probe frequency in emitted machine code

## Non-goals (initial version)

- Recursive rematerialization of operands (Cranelift also avoids this today).
- Rematerialization across exceptional control flow (we only have normal CFG).
- Any remat logic inside regalloc (we keep the separation like Cranelift +
  regalloc2).
