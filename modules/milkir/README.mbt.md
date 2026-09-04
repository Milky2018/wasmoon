# MilkIR

MilkIR is a reusable, target-independent intermediate representation for compiler middle ends. A frontend translates source operations into MilkIR, optimization passes simplify the MilkIR function, and `Milky2018/milkir/native` streams it directly into a native target selector.

Target-independent means that MilkIR operations do not encode a particular instruction set or calling convention; it does not mean that every data width is target-configurable. MilkIR pointer/reference carriers are always 64-bit: `Ptr`, `Ref`, `CallableRef`, and `OpaqueRef` each have a fixed 64-bit representation. A backend for a non-64-bit target would require an explicit IR contract change rather than interpreting these types using the host pointer width.

```text
frontend IR or bytecode
        |
        v
     MilkIR SSA  -- verify and optimize here
        |
        v
    Target VCode -- select instructions directly, then allocate registers
```

## Start with one small function

Suppose the source program contains this function:

```text
add_one(x: i32) -> i32 = x + 1
```

The following test builds the same function in MilkIR:

```moonbit check
///|
test "build add_one" {
  let builder = FunctionBuilder::FunctionBuilder("add_one")

  let x = builder.add_param(I32)
  builder.add_result(I32)

  let one = builder.iconst_i32(1)
  let answer = builder.iadd(x, one)
  builder.return_([answer])

  let func = builder.finalize()
  inspect(func.verify(), content="()")
  inspect(
    func.print(),
    content=(
      #|function add_one(v0:i32) -> i32 {
      #|block0:
      #|    v1:i32 = iconst 1
      #|    v2:i32 = iadd v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
}
```

Read the generated IR from top to bottom:

```text
function add_one(v0:i32) -> i32 {  function parameter v0 has type i32
block0:                             execution starts in block0
    v1:i32 = iconst 1              create the constant 1
    v2:i32 = iadd v0, v1           add x and 1, producing a new value
    return v2                       return that value
}
```

`finalize()` verifies the current function before returning it and raises `VerifyError` for malformed SSA, CFG, or generic instruction contracts. For extension instructions, generic verification checks only the dialect/opcode envelope and the explicit operand/result signature; the owning adapter validates dialect semantics. Finalization is a validation checkpoint, not a freeze operation: the returned `Function` remains mutable and does not carry a persistent "verified" state. `get_function()` remains the explicit escape hatch for in-progress construction and transformation code. Callers may continue transforming either value, but every consuming adapter must verify the function after its final mutation and immediately before lowering it.

The important detail is that `x`, `one`, and `answer` are not runtime integers in the MoonBit program that builds the IR. They are MilkIR `Value`s: typed handles that name values in the function being compiled.

## The six concepts to know

| Concept | Meaning | In `add_one` |
| --- | --- | --- |
| `Function` | One compilable function, including its signature and blocks. | `add_one` |
| `Type` | The static type of an IR value. | `I32` |
| `Value` | A typed name for a function parameter, block parameter, or instruction result. | `v0`, `v1`, `v2` |
| `Block` | A straight-line sequence of instructions with one exit. | `block0` |
| `Inst` | An operation that may produce one or more values. | `iconst`, `iadd` |
| `Terminator` | The final control-flow operation in a block. | `return` |

### DFG and layout ownership

`Function` is the sole owner of instruction data and value definitions. A
`Block` contains only the ordered `InstId` layout for that data; moving or
deleting an instruction changes the layout without renumbering the function's
instruction arena. Deleted instructions become lazy tombstones, while the
verifier rejects arena instructions that are neither placed nor explicitly
deleted. This keeps `Value` and `InstId` identities stable across ordinary
transformations without adding work to the normal instruction-construction
path.

The instruction layout is intentionally not a mutable public array. Use
`block.instruction_count()` and `func.block_instruction_at(block, index)` for
individual inspection. Consumers that traverse a complete block without
mutating it can use `func.block_instruction_ids(block)` to obtain a zero-copy,
read-only view, then resolve each ID with `func.instruction_by_id(id)`. The view
remains valid only until that block's layout changes.

This replaces the pre-0.15 interface that exposed
`Block.instructions : Array[Inst]`. Producers should continue to place
instructions through `FunctionBuilder` or `Block::append_inst`; optimization
passes must use the checked layout mutation methods.

`FunctionBuilder` is the normal construction API. It creates an entry block automatically and keeps track of the block that receives new instructions. For a straight-line function, the usual order is:

1. Create a builder.
2. Declare function parameters and result types.
3. Emit instructions.
4. End the current block with `return_`, `jump`, a branch, or `trap`.
5. Call `finalize`, then `verify` the function.

Lower-level producers that already have a complete `Signature` can use `Function::with_signature`. It eagerly materializes every declared function parameter in `Function.params`; retrieve those values with `func.param(index)` before emitting instructions. `Function::signature()` returns a snapshot derived from the same explicit parameter and result arrays. Do not recreate parameters with `new_value()`: that method allocates instruction results, block values, and other values after the declared function parameters.

## Opcode families

Every instruction belongs to one semantic family. `Opcode` has no source-language instruction variants or target-machine operations of its own:

| Family | Responsibility |
| --- | --- |
| `Scalar(ScalarOp)` | Constants, arithmetic, comparisons, conversions, selection, and copies. |
| `Memory(MemoryOp)` | Full-width and narrow loads and stores over an explicit base and offset value. |
| `Call(CallOp)` | Direct external-symbol calls and function-pointer calls with explicit contracts. |
| `Vector(VectorOp)` | Language-neutral V128 lane, arithmetic, comparison, conversion, and effective-address memory operations. |
| `GlobalValue(GlobalValue)` | A function-scoped, adapter-owned context field with an explicit type, stability, and alias region. |
| `Ext(ExtOp, Signature)` | Typed operations whose semantics belong to a separately owned dialect. |

Frontends must consume source-only metadata before constructing a core instruction. For example, a WebAssembly frontend resolves a SIMD memory index, alignment hint, and immediate offset while computing the effective address; MilkIR receives that address and the vector load/store semantics. A frontend uses `Ext` only when the operation genuinely requires dialect-owned validation and lowering.

### Embedding context fields

`GlobalValue` models a typed value loaded from an embedding-provided context, such as a linear-memory base pointer. Its declaration is interned in the `Function`; the instruction names that declaration and takes the context pointer explicitly. MilkIR does not know the field offset or runtime layout. The owning dialect validates the opaque `ContextField`, and its native-lowering adapter resolves it to an `EnvironmentField`.

Every declaration also states whether the field is `Stable` for the whole function invocation or `Mutable` across calls, plus the abstract region reached by the resulting pointer. Stable fields remain explicit and cheap to rematerialize: general GVN and LICM do not turn them into function-wide live ranges. Mutable fields may be reused across unrelated heap stores but are invalidated by calls and unknown memory writes. Targets materialize the semantic occurrences they receive rather than applying a second reuse policy. These contracts permit local redundancy elimination without pinning a physical register or hard-coding an embedding layout into MilkIR.

### Semantic ownership

MilkIR records the optimizer-visible facts of each built-in opcode in one semantic summary: whether it may trap, whether it reads or writes memory, and whether it has another observable effect. Dead-code elimination, loop optimization, and global value numbering derive their safety decisions from that summary instead of maintaining independent opcode lists. Unknown extension operations are conservatively treated as trapping and effectful.

Other concerns remain with the stage that implements them. The verifier owns operand and result contracts, the printer owns textual syntax, direct acyclic rewriting owns local canonical forms, and native lowering owns instruction selection. These are different responsibilities rather than duplicate semantic facts.

When adding a built-in opcode:

1. Add its operand and result contract to the verifier.
2. Classify its trap, memory, and observable-effect behavior in the opcode semantic summary.
3. Add its textual representation to the printer.
4. Add its instruction selection to `milkir/native` or the owning dialect adapter.
5. Add a direct rewrite only when it is locally profitable and preserves the
   instruction's semantic contract.

The built-in family matches in those stages are exhaustive, so adding a new family or operation leaves a compiler error until its required behavior is supplied. The direct rewriter is intentionally conservative: operations without a proven local canonicalization remain unchanged.

## Why values are called SSA values

SSA means *static single assignment*: each MilkIR `Value` is defined exactly once. An instruction never changes an existing value; it creates a new one.

For example, a source-language assignment such as `x = x + 1` should not overwrite the MilkIR value for the old `x`. The frontend emits a fresh value instead:

```text
v0:i32 = ...          old x
v1:i32 = iconst 1
v2:i32 = iadd v0, v1  new x
```

This makes data dependencies explicit. An optimizer can see that `v2` depends on `v0` and `v1` without reconstructing the history of a mutable variable.

Every value belongs to one function and has one `Type`. The core types are `I32`, `I64`, `F32`, `F64`, `V128`, `Ptr`, `Ref`, `CallableRef`, and `OpaqueRef`. The four pointer/reference carrier types are fixed-width 64-bit values, not aliases for the host's native pointer type.

## Comparisons do not require extra blocks

Use `select` when both candidate values are already available. The next function returns the larger of two signed `i32` values:

```moonbit check
///|
test "build max_i32 with select" {
  let builder = FunctionBuilder::FunctionBuilder("max_i32")
  let lhs = builder.add_param(I32)
  let rhs = builder.add_param(I32)
  builder.add_result(I32)

  let lhs_is_greater = builder.icmp_sgt(lhs, rhs)
  let result = builder.select(lhs_is_greater, lhs, rhs)
  builder.return_([result])

  let func = builder.finalize()
  inspect(func.verify(), content="()")
  inspect(func.print().contains("icmp.sgt"), content="true")
  inspect(func.print().contains("select"), content="true")
}
```

`icmp_sgt` produces an `I32` condition. `select(condition, when_nonzero, when_zero)` chooses a value without changing control flow.

## Control flow: blocks and terminators

A block contains zero or more instructions and exactly one terminator. Once a terminator has been emitted, switch to a different block before emitting more instructions.

The common terminators are:

| Builder method | Meaning |
| --- | --- |
| `return_(values)` | Return values to the caller. |
| `jump(target, args)` | Continue in another block and pass its arguments. |
| `brnz(condition, then_block, else_block)` | Branch to the first target when the condition is nonzero. |
| `brz(condition, then_block, else_block)` | Branch to the first target when the condition is zero. |
| `br_table(index, targets, default)` | Choose one of several targets. |
| `trap(reason)` | Stop execution abnormally. |

Here is the shape of a conditional function before considering how values cross block boundaries:

```text
                 +--------------+
                 |    block0    |
                 | test cond    |
                 +------+-------+
                        |
              +---------+---------+
              |                   |
              v                   v
        +-----------+       +-----------+
        | then_block|       | else_block|
        +-----+-----+       +-----+-----+
              |                   |
              +---------+---------+
                        |
                        v
                 +------------+
                 | join_block |
                 +------------+
```

## Passing values between blocks

MilkIR uses block parameters instead of phi instructions. A block parameter is a value defined at the start of a block. Every jump to that block supplies the argument that the parameter receives on that edge.

The following function computes `input + 1` when `condition` is nonzero and returns `input` otherwise:

```moonbit check
///|
test "pass a value into a join block" {
  let builder = FunctionBuilder::FunctionBuilder("add_if")
  let input = builder.add_param(I32)
  let condition = builder.add_param(I32)
  builder.add_result(I32)

  let add_block = builder.create_block()
  let unchanged_block = builder.create_block()
  let join_block = builder.create_block()
  let result = builder.add_block_param(join_block, I32)

  builder.brnz(condition, add_block, unchanged_block)

  builder.switch_to_block(add_block)
  let one = builder.iconst_i32(1)
  let incremented = builder.iadd(input, one)
  builder.jump(join_block, [incremented])

  builder.switch_to_block(unchanged_block)
  builder.jump(join_block, [input])

  builder.switch_to_block(join_block)
  builder.return_([result])

  let func = builder.finalize()
  inspect(func.verify(), content="()")
  inspect(func.blocks.length(), content="4")
  inspect(func.blocks[3].params.length(), content="1")
}
```

Focus on the three names around the join:

```text
add_block       --jump [incremented]--+
                                         >-- join_block(result) -- return result
unchanged_block --jump [input]----------+
```

`result` is defined by `join_block`, not by either predecessor. On the `add_block` edge it receives `incremented`; on the other edge it receives `input`. If a join block has multiple parameters, each incoming jump must pass arguments in the same order.

## Verification

Always verify a function after construction and after transformations that may change its structure:

```moonbit nocheck
let func = builder.finalize()
func.verify()
```

`Function::verify` checks core structural and local typing rules, including:

- the function contains at least one block;
- each referenced operand has been defined;
- each block has a terminator;
- core instructions have the expected operand arity;
- operands that must agree have matching types;
- comparison results have type `I32`.

Verification is a useful construction guard, not a complete proof of every frontend, dialect, dominance, calling-convention, or embedding invariant. Frontends and dialects should perform any additional semantic checks their input requires.

## Optimization

Optimization lives in the `Milky2018/milkir/optimize` package within this module.
Import it alongside `Milky2018/milkir`; the root package owns the IR and does not
forward optimizer APIs. Optimization mutates a `Function` and returns an
`@optimize.OptResult` whose `changed` field reports whether any pass changed the IR.

```moonbit check
///|
test "fold a constant expression" {
  let builder = FunctionBuilder::FunctionBuilder("constant_answer")
  builder.add_result(I32)
  let ten = builder.iconst_i32(10)
  let twenty = builder.iconst_i32(20)
  let answer = builder.iadd(ten, twenty)
  builder.return_([answer])

  let func = builder.finalize()
  let result = @optimize.optimize_with_level(func, O1)

  inspect(result.changed, content="true")
  inspect(@optimize.instruction_count(func), content="1")
  inspect(func.print().contains("iconst 30"), content="true")
  inspect(func.verify(), content="()")
}
```

The optimization levels are:

| Level | Intended use |
| --- | --- |
| `O0` | Minimal pipeline: removes dead code plus constant and unused block parameters. |
| `O1` | Inexpensive simplification: mandatory cleanup, constant folding, alias canonicalization, and dead-code elimination. |
| `O2` | The default pipeline: O1-style cleanup plus direct acyclic rewriting, budgeted memory GVN, unbudgeted cheap value numbering, and CFG simplification. |
| `O3` | Mandatory normalization, checked loop transformations, then one acyclic rewrite/GVN pipeline and final cleanup. |

Use `@optimize.optimize(func)` for the default pipeline or
`@optimize.optimize_with_level(func, level)` when the caller chooses the level
explicitly. Optimizers assume a valid SSA and block-parameter structure. Verify
before optimization when the input comes from a frontend, then verify again
after developing a new transformation.

The optimizer works directly on the Function DFG. Rules are handwritten and
dispatched by root opcode; there is no separate e-node graph, generated matcher
or saturation loop. Staged rewrites require a strictly cheaper expression and
must not rebuild shared definitions. Integer widths, vector lanes, floating
NaNs/signed zero and trapping operations remain semantic constraints, not
optional profitability hints. See the repository's
[optimizer design](../../docs/milkir-optimizer.md) and
[rule migration ledger](../../docs/milkir-rewrite-inventory.md).

### Counted-loop unrolling at O3

O3 unrolls only natural loops for which analysis produces a complete plan. The supported form has one preheader, one header comparison, one body path, one latch/back edge, and one exit; body and latch blocks must not introduce additional block parameters. Initial values, bounds, and steps must resolve to constants through any loop-external copy chain. The induction value may be I32 or I64 and may use signed or unsigned `<`, `<=`, `>`, or `>=` comparisons. Reversed comparison operands and inverted conditional-branch polarity are normalized before analysis. Increasing and decreasing updates use checked arithmetic, so a loop whose final update would wrap is rejected.

All header block parameters are treated as loop-carried state. Full unrolling is limited to at most eight source iterations, while larger proven loops use factor-two unrolling with one peeled iteration for odd trip counts. Both strategies cap newly cloned instructions at 64. Cloning assigns fresh instruction and value IDs, remaps zero-result and multi-result instructions, preserves metadata and effect order, and verifies correctly with calls, loads, stores, and traps.

The pass leaves the function unchanged when the CFG shape is unsupported, a bound or step is dynamic, the trip count exceeds the analysis limit, an operand or latch edge cannot be mapped, arithmetic may wrap, or code growth exceeds the budget.

## Calls, memory, and traps

The concepts below matter when a frontend moves beyond pure arithmetic into embedding and effect semantics.

### External calls

`ExternalSymbol` names a symbol outside the IR function. `CallOp::Direct(symbol, signature)` and `CallOp::Pointer(num_args, num_results)` are treated conservatively by core optimizations because calls may observe or change state. Direct calls carry operand/result signatures that the verifier checks; pointer calls carry explicit argument and result counts.

`CallOp::Pointer` has a generic operand contract:

1. operand 0 is the function pointer;
2. operands 1 and later are ordinary arguments;
3. `num_args` counts every operand after the callee pointer.

An embedding adapter may assign roles such as VMContext to those arguments when it chooses a calling convention, but that role is not part of the core opcode contract.

### Traps and effects

`Trap(reason)` and `TrapExit(reason)` terminators end execution without normal results. Stores, calls, traps, and unknown extension operations are observable or potentially observable. Optimizations must not delete or reorder them unless a stronger analysis proves that doing so preserves behavior.

## Dialect-specific operations

`Ext(ExtOp, Signature)` represents dialect-specific operations. MilkIR stores only a dialect name, opcode name, integer immediates, and an explicit operand/result contract. Validator closures are not part of `Function`; the dialect package owns builders, semantic validation, decoding, and lowering.

`Function::verify` and `FunctionBuilder::finalize` validate generic IR structure without interpreting dialect semantics. At the adapter seam, `Function::verify_with_dialect_validator` receives the owned dialect name plus explicit instruction and global-value validators, rejects data owned by another dialect, and converts diagnostics into `VerifyError::UnverifiableInstruction`. Dialect lowering likewise requires explicit adapter validation, so validation behavior depends only on the adapter selected by the consumer, never on function construction history.

```moonbit check
///|
test "validate a dialect opcode descriptor" {
  let descriptor = ExtOpDescriptor::ExtOpDescriptor("demo", "checked_add", 1)
  let opcode = ExtOp::ExtOp("demo", "checked_add", FixedArray::make(1, 32))

  inspect(opcode.matches_descriptor(descriptor), content="true")
  inspect(descriptor.expected_immediate_count(), content="1")
}
```

Core optimizations treat extension operations conservatively because MilkIR cannot infer whether an unknown operation reads memory, writes memory, traps, or depends on embedding state.

## Typical frontend workflow

A frontend using MilkIR normally follows this sequence:

1. Map source types to MilkIR `Type`s.
2. Create a `FunctionBuilder`, then declare the function parameters and results.
3. Translate each source basic block, keeping a map from source values to MilkIR `Value`s.
4. Represent merges and loop-carried values with block parameters and jump arguments.
5. Finalize and verify the function.
6. Optimize it at the desired level.
7. Stream it into a native target with `Milky2018/milkir/native`.

For debugging, `Function::print` produces a readable textual view and `CFG::to_dot` produces Graphviz DOT for the control-flow graph. `CFG` also provides predecessors, successors, traversal orders, dominators, back edges, and loop discovery.

## Related packages

MilkIR focuses on target-independent SSA construction, verification, control-flow analysis, and optimization. Other compiler stages build on it through separate packages:

| Compiler stage | Package |
| --- | --- |
| SSA construction, verification, CFGs, and optimization | `Milky2018/milkir` |
| Optional WebAssembly extension operations | `Milky2018/wasm_milkir` |
| Direct native target lowering | `Milky2018/milkir/native` |
| Target instruction selection and ABI details | `Milky2018/aarch64_target` and `Milky2018/x64_target` |
