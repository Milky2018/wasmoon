# MilkIR

MilkIR is a reusable, target-independent intermediate representation for compiler middle ends. A frontend translates source operations into MilkIR, optimization passes simplify the MilkIR function, and a lowering package such as `Milky2018/milkir_machv` turns it into machine-oriented IR.

```text
frontend IR or bytecode
        |
        v
     MilkIR SSA  -- verify and optimize here
        |
        v
      MachV IR   -- select instructions and allocate registers later
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

`finalize()` verifies the current function before returning it and raises `VerifyError` for malformed SSA, CFG, or instruction contracts. `get_function()` remains the explicit escape hatch for in-progress construction and transformation code; callers that mutate a function after finalization must verify it again.

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

`FunctionBuilder` is the normal construction API. It creates an entry block automatically and keeps track of the block that receives new instructions. For a straight-line function, the usual order is:

1. Create a builder.
2. Declare function parameters and result types.
3. Emit instructions.
4. End the current block with `return_`, `jump`, a branch, or `trap`.
5. Call `finalize`, then `verify` the function.

Lower-level producers that already have a complete `Signature` can use `Function::with_signature`. It eagerly materializes every declared function parameter in `Function.params`; retrieve those values with `func.param(index)` before emitting instructions. `Function::signature()` returns a snapshot derived from the same explicit parameter and result arrays. Do not recreate parameters with `new_value()`: that method allocates instruction results, block values, and other values after the declared function parameters.

## Why values are called SSA values

SSA means *static single assignment*: each MilkIR `Value` is defined exactly once. An instruction never changes an existing value; it creates a new one.

For example, a source-language assignment such as `x = x + 1` should not overwrite the MilkIR value for the old `x`. The frontend emits a fresh value instead:

```text
v0:i32 = ...          old x
v1:i32 = iconst 1
v2:i32 = iadd v0, v1  new x
```

This makes data dependencies explicit. An optimizer can see that `v2` depends on `v0` and `v1` without reconstructing the history of a mutable variable.

Every value belongs to one function and has one `Type`. The core types are `I32`, `I64`, `F32`, `F64`, `V128`, `Ptr`, `Ref`, `CallableRef`, and `OpaqueRef`.

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

Optimization mutates a `Function` and returns an `OptResult` whose `changed` field reports whether any pass changed the IR.

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
  let result = optimize_with_level(func, O1)

  inspect(result.changed, content="true")
  inspect(instruction_count(func), content="1")
  inspect(func.print().contains("iconst 30"), content="true")
  inspect(func.verify(), content="()")
}
```

The optimization levels are:

| Level | Intended use |
| --- | --- |
| `O0` | Minimal pipeline: removes dead code plus constant and unused block parameters. |
| `O1` | The standard Cranelift-style simplification pipeline. |
| `O2` | The default level and an alias for the standard `O1` pass set. |
| `O3` | The `O2` pipeline, loop-invariant code motion, checked counted-loop unrolling, strength reduction, and a final `O2` cleanup. |

Use `optimize(func)` for the default pipeline or `optimize_with_level(func, level)` when the caller chooses the level explicitly. Optimizers assume a valid SSA and block-parameter structure. Verify before optimization when the input comes from a frontend, then verify again after developing a new transformation.

### Counted-loop unrolling at O3

O3 unrolls only natural loops for which analysis produces a complete plan. The supported form has one preheader, one header comparison, one body path, one latch/back edge, and one exit; body and latch blocks must not introduce additional block parameters. Initial values, bounds, and steps must resolve to constants through any loop-external copy chain. The induction value may be I32 or I64 and may use signed or unsigned `<`, `<=`, `>`, or `>=` comparisons. Reversed comparison operands and inverted conditional-branch polarity are normalized before analysis. Increasing and decreasing updates use checked arithmetic, so a loop whose final update would wrap is rejected.

All header block parameters are treated as loop-carried state. Full unrolling is limited to at most eight source iterations, while larger proven loops use factor-two unrolling with one peeled iteration for odd trip counts. Both strategies cap newly cloned instructions at 64. Cloning assigns fresh instruction and value IDs, remaps zero-result and multi-result instructions, preserves metadata and effect order, and verifies correctly with calls, loads, stores, and traps.

The pass leaves the function unchanged when the CFG shape is unsupported, a bound or step is dynamic, the trip count exceeds the analysis limit, an operand or latch edge cannot be mapped, arithmetic may wrap, or code growth exceeds the budget.

## Calls, memory, and traps

The concepts below matter when a frontend moves beyond pure arithmetic into embedding and effect semantics.

### Stack slots and pointers

Stack slots are per-function abstract local storage objects. `StackAddr(slot)` produces an address-like value for lowering; MilkIR does not decide the final frame layout. Lower-level code can use pointer operations such as `LoadPtr`, `StorePtr`, narrow pointer loads and stores, and `CallPtr`.

### External calls

`ExternalSymbol` names a symbol outside the IR function. `Call(symbol, signature)`, `CallIndirect(signature)`, and `CallPtr(num_args, num_results)` are treated conservatively by core optimizations because calls may observe or change state. Direct and indirect calls carry operand/result signatures that the verifier checks; pointer calls carry explicit argument and result counts.

`CallPtr` has a generic operand contract:

1. operand 0 is the function pointer;
2. operand 1 is an explicit callee environment;
3. operands 2 and later are user arguments.

An embedding that does not need an environment must still pass an explicit sentinel value. The embedding and lowering layer define the pointer meaning, sentinel, calling convention, and trap behavior.

### Traps and effects

`Trap(reason)` and `TrapExit(reason)` end execution without normal results. Stores, calls, pointer calls, traps, and unknown extension operations are observable or potentially observable. Optimizations must not delete or reorder them unless a stronger analysis proves that doing so preserves behavior.

## Dialect-specific operations

`Ext(ExtOp, Signature)` represents dialect-specific operations. MilkIR stores a dialect name, opcode name, integer immediates, and an explicit operand/result contract, while the dialect package provides builders, semantic validation, decoding, and lowering.

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
7. Lower it to the next IR, for example with `Milky2018/milkir_machv`.

For debugging, `Function::print` produces a readable textual view and `CFG::to_dot` produces Graphviz DOT for the control-flow graph. `CFG` also provides predecessors, successors, traversal orders, dominators, back edges, and loop discovery.

## Related packages

MilkIR focuses on target-independent SSA construction, verification, control-flow analysis, and optimization. Other compiler stages build on it through separate packages:

| Compiler stage | Package |
| --- | --- |
| SSA construction, verification, CFGs, and optimization | `Milky2018/milkir` |
| Optional WebAssembly extension operations | `Milky2018/wasm_milkir` |
| Lowering from MilkIR to machine-oriented IR | `Milky2018/milkir_machv` |
| Target instruction selection and ABI details | `Milky2018/aarch64_target` and `Milky2018/x64_target` |
