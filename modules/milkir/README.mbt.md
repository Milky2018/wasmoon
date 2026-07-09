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

## Boundary

`milkir` is generic compiler infrastructure. It should not depend on Wasmoon
runtime concepts, embedding context layouts, WASI, or machine-code emission.

Dialect-specific operations should travel through the generic `ExtOp`
extension hook. The WebAssembly dialect is owned by `Milky2018/wasm_milkir`,
not by MilkIR core.
