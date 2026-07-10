# machv

Reusable virtual-register machine IR.

`machv` models low-level machine code before final register allocation and
emission. It provides virtual registers, physical-register descriptions,
machine instructions, blocks, ABI data, target ISA descriptors, printing, and
machine-function helpers.

## Packages

- `Milky2018/machv`: root facade for machine functions and common helpers.
- `Milky2018/machv/abi`: ABI locations, registers, calling-convention data,
  and runtime-context layout abstractions.
- `Milky2018/machv/instr`: virtual machine instruction and terminator model.
- `Milky2018/machv/block`: basic-block representation.
- `Milky2018/machv/isa`: generic ISA descriptions and target selection.
- `Milky2018/machv/isa/aarch64`, `Milky2018/machv/isa/amd64`: target-specific
  register descriptions.

## When to use it

Use MachV after instruction selection, but before final physical register
allocation and encoding. It is the place to model virtual registers, machine
instructions, ABI locations, block successors, call metadata, and terminators.

## Example: build a virtual-register function

`FunctionBuilder` is the public construction API. Passes can read the finished
`Function` directly, while mutation stays behind the builder or internal
transformation helpers.

```moonbit check
///|
test "build a virtual-register copy" {
  let builder = FunctionBuilder::FunctionBuilder("copy")
  let src = builder.add_param(Int)
  let dst = builder.new_vreg(Int)
  builder.append(Move, uses=[Virtual(src)], defs=[{ reg: Virtual(dst) }])
  |> ignore
  builder.terminate(Return([Virtual(dst)]))
  let func = builder.finish()
  inspect(func.blocks.length(), content="1")
  inspect(func.blocks[0].insts.length(), content="1")
  inspect(func.blocks[0].terminator is Some(Return(_)), content="true")
}
```

## Example: build control flow

Blocks are created through the builder and terminated explicitly.

```moonbit check
///|
test "build a branch" {
  let builder = FunctionBuilder::FunctionBuilder("branch")
  let cond = builder.add_param(Int)
  let then_block = builder.create_block()
  let else_block = builder.create_block()
  builder.terminate(Branch(Virtual(cond), then_block, else_block))
  builder.switch_to_block(then_block)
  builder.terminate(Return([]))
  builder.switch_to_block(else_block)
  builder.terminate(Return([]))
  let func = builder.finish()
  inspect(func.blocks.length(), content="3")
  inspect(func.blocks[0].terminator is Some(Branch(_, _, _)), content="true")
}
```

## Integration

MachV functions carry virtual registers, ABI locations, calls, and symbolic
external references through allocation and emission. Target packages provide
the instruction and register details needed to turn those functions into
machine code.
