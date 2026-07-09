# regalloc

Target-independent register allocation algorithm.

`regalloc` models allocation programs, machine environments, live ranges,
allocation decisions, move resolution, spill planning, and verification without
depending on a concrete machine IR.

## Package

- `Milky2018/regalloc`: allocation data structures, allocator entry points,
  and verifier APIs.
- `Milky2018/regalloc/backtracking`: expert hooks for clients that integrate
  the production backtracking allocator with their own machine IR adapter.

## When to use it

Use `regalloc` when you have a machine-independent allocation problem: virtual
registers, physical registers, instructions, use/def operands, clobbers, and a
control-flow graph. It deliberately does not know about concrete IRs, frontend
dialects, or target instruction formats.

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
  let program = Program::Program([r0, r1])
  let block = Block::Block(0)
  let inst = Instruction::Instruction(0)
  inst.add_operand(Operand::def(v0))
  inst.add_operand(Operand::use_reg(v1))
  block.append(inst)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v0) == Some(Reg(r0)), content="true")
  inspect(allocation.location_of(v1) == Some(Reg(r1)), content="true")
  inspect(verify_allocation(program, allocation), content="()")
}
```

## Example: configure allocation

`RegallocConfig` controls user-facing allocation behavior. By default
`allocate` verifies the result before returning it; callers that run their own
validation can disable that check.

```moonbit check
///|
test "allocate with explicit configuration" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let program = Program::Program([r0])
  let block = Block::Block(0)
  let inst = Instruction::Instruction(0)
  inst.add_operand(Operand::def(v0))
  block.append(inst)
  program.add_block(block)
  let config = RegallocConfig::RegallocConfig(verify=false)
  let allocation = allocate(program, config~)
  inspect(config.strategy() == LinearScan, content="true")
  inspect(allocation.location_of(v0) == Some(Reg(r0)), content="true")
}
```

## Boundary

This module should stay a pure algorithmic layer. Machine-IR-specific adapters
belong in modules such as `machv_regalloc`.
