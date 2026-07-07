# milkir

Reusable Cranelift-like SSA intermediate representation.

`milkir` provides compiler IR data structures, builders, verification, CFG
helpers, printing, and optimization passes. It is intended as a reusable
middle-end layer for MoonBit compiler projects.

## Package

- `Milky2018/milkir`: SSA values, blocks, instructions, terminators,
  signatures, `IRBuilder`, verification, CFG utilities, and optimization
  drivers.

## When to use it

Use MilkIR when a frontend needs a target-independent SSA form before
instruction selection. A typical pipeline builds a `Function`, verifies it,
runs one or more optimization passes, then lowers it through `isa_target` into
MachV.

## Example: build and verify SSA

`IRBuilder` owns the common workflow: declare parameters/results, create
blocks, emit SSA values, and finish each block with a terminator.

```moonbit check
///|
test "build an add function with IRBuilder" {
  let builder = IRBuilder::new("add_i32")
  let lhs = builder.add_param(I32)
  let rhs = builder.add_param(I32)
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let sum = builder.iadd(lhs, rhs)
  builder.return_([sum])
  let func = builder.get_function()
  inspect(func.verify(), content="()")
  inspect(func.blocks.length(), content="1")
  inspect(instruction_count(func), content="1")
}
```

## Example: run a small optimization pass

Optimization passes mutate the function and report whether they changed it.
This example folds two constants and then verifies the optimized function.

```moonbit check
///|
test "fold constants in a MilkIR function" {
  let builder = IRBuilder::new("const_add")
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let lhs = builder.iconst_i32(10)
  let rhs = builder.iconst_i32(20)
  let sum = builder.iadd(lhs, rhs)
  builder.return_([sum])
  let func = builder.get_function()
  let before = instruction_count(func)
  let result = fold_constants(func)
  inspect(result.changed, content="true")
  inspect(instruction_count(func) <= before, content="true")
  inspect(func.verify(), content="()")
}
```

## Boundary

`milkir` is generic compiler infrastructure. It should not depend on Wasmoon
runtime concepts, VMContext layouts, WASI, or machine-code emission.
