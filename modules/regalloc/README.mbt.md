# regalloc

Target-independent register allocation algorithm.

`regalloc` models allocation programs, machine environments, live ranges,
allocation decisions, move resolution, spill planning, and verification without
depending on a concrete machine IR.

## Package

- `Milky2018/regalloc`: allocation data structures, allocator entry points,
  policy helpers, and verifier APIs.

## When to use it

Use `regalloc` when you have a machine-independent allocation problem: virtual
registers, physical registers, instructions, use/def operands, clobbers, and a
control-flow graph. It deliberately does not know about MachV, Wasm, x64, or
AArch64 instruction formats.

## Example: allocate an abstract program

The smallest program has physical registers, one block, and instructions with
virtual-register operands. The allocator returns locations for each virtual
register and can be checked with the verifier.

```moonbit check
///|
test "allocate virtual registers to physical registers" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0, r1])
  let block = Block::new(0)
  let inst = Instruction::new(0)
  inst.add_operand(Operand::def(v0))
  inst.add_operand(Operand::use_reg(v1))
  block.append(inst)
  program.add_block(block)
  let allocation = allocate_linear_scan(program)
  inspect(allocation.location_of(v0) == Some(Reg(r0)), content="true")
  inspect(allocation.location_of(v1) == Some(Reg(r1)), content="true")
  inspect(verify_allocation(program, allocation), content="()")
}
```

## Example: inspect live ranges before allocation

Live ranges are independent of the allocator choice. Compiler authors can use
them to debug why a value was spilled or why two values could not share a
register.

```moonbit check
///|
test "compute a live range across two instructions" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let def_inst = Instruction::new(0)
  def_inst.add_operand(Operand::def(v0))
  block.append(def_inst)
  let use_inst = Instruction::new(1)
  use_inst.add_operand(Operand::use_reg(v0))
  block.append(use_inst)
  program.add_block(block)
  let ranges = build_live_ranges(program)
  let range = ranges.get_by_vreg(v0).unwrap()
  inspect(range.start() == Some(ProgramPoint::new(0, 0)), content="true")
  inspect(range.end() == Some(ProgramPoint::new(0, 1)), content="true")
  inspect(range.uses.length(), content="2")
}
```

## Boundary

This module should stay a pure algorithmic layer. Machine-IR-specific adapters
belong in modules such as `machv_regalloc`.
