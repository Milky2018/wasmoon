# milkir

Reusable Cranelift-like SSA intermediate representation.

`milkir` provides compiler IR data structures, builders, verification, CFG
helpers, printing, and optimization drivers. It is intended as a reusable
middle-end layer for MoonBit compiler projects.

## Package

- `Milky2018/milkir`: SSA values, blocks, instructions, terminators,
  signatures, `FunctionBuilder`, verification, CFG utilities, and optimization
  drivers.

## When to use it

Use MilkIR when a frontend needs a target-independent SSA form before
instruction selection. A typical pipeline builds a `Function`, verifies it,
runs one or more optimization passes, then lowers it through `milkir_machv` into
MachV.

## Semantic Model

MilkIR is an SSA IR. Every `Value` belongs to exactly one `Function`, has one
static `Type`, and is defined by a function parameter, a block parameter, or an
instruction result. Instruction operands may only reference values that are
defined in the same function. `Function::verify` checks that operands are
defined, that every block has a terminator, and that core instructions satisfy
their basic arity and type rules.

Blocks use block parameters instead of phi instructions. A `Jump(target, args)`
transfers control to `target` and binds each argument to the corresponding block
parameter. Frontends should pass values through block arguments rather than
reusing predecessor-local values in successor blocks. Conditional terminators
choose a successor; when a successor needs values from multiple predecessors,
route each predecessor through a `Jump` that supplies the join block arguments.

Terminators are the only control-flow exits from a block. `Return(values)`
returns function results, `Trap(reason)` and `TrapExit(reason)` end execution
without normal results, and branch/jump terminators transfer control inside the
same function. Traps are semantic exits: optimizations must not move trapping or
effectful work across a trap in a way that changes observable behavior.

Stack slots are per-function abstract local storage objects. `StackAddr(slot)`
materializes an address-like value for lowering; MilkIR core does not prescribe
where the slot lives in the final frame. Pointer operations such as `LoadPtr`,
`StorePtr`, narrow pointer loads/stores, and `CallPtr` operate on raw pointer
values and are intended for lower-level compiler or trampoline code.

`ExternalSymbol` names a symbol outside the IR function. `Call(symbol)`,
`CallIndirect(signature)`, and `CallPtr(num_args, num_results)` are effectful
unless a later, dialect-specific analysis proves otherwise. Core optimization
passes therefore treat calls conservatively: calls may read memory, pointer
calls may write memory, and calls are not dead-code-eliminated just because
their results are unused.

`CallPtr` has a generic operand contract, not an embedding-specific one:
operand 0 is the function pointer, operand 1 is an explicit callee environment,
and operands 2..N are user arguments. If an embedding does not need a callee
environment, it must still choose and pass an explicit sentinel value at the
builder boundary. The meaning of the pointer, environment, calling convention,
and trap behavior is supplied by the embedding and lowering layer, not by
MilkIR core.

`Ext(ExtOp)` is the extension point for dialect-specific operations. MilkIR
records the dialect name, opcode name, and integer immediates, while dialect
packages own builders, validation, decoding, and lowering. Use
`ExtOpDescriptor` to describe the accepted immediate layout at the dialect
boundary. Core optimization treats extension operations conservatively because
MilkIR cannot know whether a foreign opcode reads memory, writes memory, traps,
or depends on embedding state.

Optimization passes may assume the verified SSA and block-parameter structure
above. They may rewrite pure arithmetic, constants, copies, aliases, and CFG
shape when value definitions and block arguments remain valid. They must keep
memory order around stores, calls, pointer calls, and extension operations
unless an explicit analysis proves a stronger fact. Dialect and embedding
packages are responsible for preserving any semantics that MilkIR core cannot
see.

## Example: build and verify SSA

`FunctionBuilder` owns the common workflow: declare parameters/results, emit
the entry block, create additional blocks when control flow needs them, switch
to the block being translated, and finish each block with a terminator. A new
builder starts with an entry block as the current block, so simple straight-line
functions can emit instructions immediately.

```moonbit check
///|
test "build an add function with FunctionBuilder" {
  let builder = FunctionBuilder::FunctionBuilder("add_i32")
  let lhs = builder.add_param(I32)
  let rhs = builder.add_param(I32)
  builder.add_result(I32)
  let sum = builder.iadd(lhs, rhs)
  builder.return_([sum])
  let func = builder.finalize()
  inspect(func.verify(), content="()")
  inspect(func.blocks.length(), content="1")
  inspect(instruction_count(func), content="1")
}
```

## Example: build a join with block parameters

This example builds a small diamond. The `join` block has one block parameter,
and both predecessors jump to it with the value that should be bound on that
edge. This is the MilkIR equivalent of a phi node.

```moonbit check
///|
test "build a conditional join with a block parameter" {
  let builder = FunctionBuilder::FunctionBuilder("select_via_blocks")
  let input = builder.add_param(I32)
  let cond = builder.add_param(I32)
  builder.add_result(I32)

  let then_block = builder.create_block()
  let else_block = builder.create_block()
  let join_block = builder.create_block()
  let join_value = builder.add_block_param(join_block, I32)

  builder.brnz(cond, then_block, else_block)

  builder.switch_to_block(then_block)
  let one = builder.iconst_i32(1)
  let then_value = builder.iadd(input, one)
  builder.jump(join_block, [then_value])

  builder.switch_to_block(else_block)
  let zero = builder.iconst_i32(0)
  let else_value = builder.iadd(input, zero)
  builder.jump(join_block, [else_value])

  builder.switch_to_block(join_block)
  builder.return_([join_value])

  let func = builder.finalize()
  inspect(func.verify(), content="()")
  inspect(func.blocks.length(), content="4")
  inspect(func.blocks[3].params.length(), content="1")
}
```

## Example: run a small optimization pass

The public optimization drivers mutate the function and report whether they
changed it. This example folds two constants and then verifies the optimized
function.

```moonbit check
///|
test "fold constants in a MilkIR function" {
  let builder = FunctionBuilder::FunctionBuilder("const_add")
  builder.add_result(I32)
  let lhs = builder.iconst_i32(10)
  let rhs = builder.iconst_i32(20)
  let sum = builder.iadd(lhs, rhs)
  builder.return_([sum])
  let func = builder.finalize()
  let before = instruction_count(func)
  let result = optimize_with_level(func, OptLevel::from_int(1))
  inspect(result.changed, content="true")
  inspect(instruction_count(func) <= before, content="true")
  inspect(func.verify(), content="()")
}
```

## Example: validate an extension opcode

Core MilkIR stores extension opcodes without importing a dialect package. The
dialect should publish descriptors and builders so users can validate the
opcode before lowering.

```moonbit check
///|
test "describe and validate a MilkIR extension opcode" {
  let descriptor = ExtOpDescriptor::ExtOpDescriptor("demo", "checked_add", 1)
  let opcode = ExtOp::ExtOp("demo", "checked_add", FixedArray::make(1, 32))
  inspect(opcode.matches_descriptor(descriptor), content="true")
  inspect(descriptor.expected_immediate_count(), content="1")
}
```

## Boundary

`milkir` is generic compiler infrastructure. It should not depend on Wasmoon
runtime concepts, embedding context layouts, WASI, or machine-code emission.

Dialect-specific operations should travel through the generic `ExtOp`
extension hook. `ExtOpDescriptor` lets dialect packages describe and validate
their own immediate layouts without teaching MilkIR core those dialect
semantics. The WebAssembly dialect is owned by `Milky2018/wasm_milkir`, not by
MilkIR core.
