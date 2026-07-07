# machv

Reusable virtual-register machine IR.

`machv` models low-level machine code before final register allocation and
emission. It provides virtual registers, physical-register descriptions,
machine instructions, blocks, ABI data, target ISA descriptors, printing, and
verification helpers.

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
instructions, ABI locations, block successors, clobbers, stack slots, and
terminators.

## Example: build a virtual-register function

The `AbstractFunction` API is useful for target-independent tests, adapters,
and simple machine-IR construction. A real target lowering usually fills the
same concepts from MilkIR.

```moonbit check
///|
test "build and verify a virtual-register copy" {
  let func = AbstractFunction::new("copy")
  let entry = func.new_block()
  let src = func.add_param(Int)
  let dst = func.new_vreg(Int)
  let mov = func.new_inst(Move)
  mov.add_operand(Operand::use_reg(Virtual(src)))
  mov.add_operand(Operand::def(Virtual(dst)))
  entry.append(mov)
  entry.set_terminator(TermReturn([Virtual(dst)]))
  inspect(func.verify(), content="()")
  inspect(func.blocks.length(), content="1")
  inspect(entry.instructions.length(), content="1")
}
```

## Example: record call-side ABI effects

Call instructions can declare clobbers and stack effects so allocation and
emission can preserve live values correctly.

```moonbit check
///|
test "represent a call clobber and outgoing stack frame" {
  let func = AbstractFunction::new("call_host")
  let entry = func.new_block()
  let call = func.new_inst(Call("host.print"))
  call.add_clobber({ index: 0, class: Int })
  call.set_stack_effect(CallFrame(16))
  entry.append(call)
  inspect(call.clobbers.length(), content="1")
  debug_inspect(call.stack_effect, content="CallFrame(16)")
}
```

## Boundary

`machv` should remain independent from Wasmoon. Product-specific runtime
symbols, WASI, VMContext fields, and native FFI glue belong in embedding
modules such as `wasmoon_jit`.
