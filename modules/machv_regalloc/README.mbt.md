# machv_regalloc

MachV adapter for the reusable register allocator.

`machv_regalloc` bridges `Milky2018/machv` virtual-register functions to the
target-independent `Milky2018/regalloc` algorithm. It projects MachV into the
generic allocation model, applies allocation output, and keeps edge-copy and
layout behavior compatible with MachV emission.

## Packages

- `Milky2018/machv_regalloc`: projection, allocation entry points, application,
  validation, spill handling, and output construction.
- `Milky2018/machv_regalloc/layout`: block layout utilities for MachV
  functions.

## When to use it

Use `machv_regalloc` when your code is already in MachV and you want to reuse
the target-independent allocator. This package projects MachV virtual
registers into `regalloc.Program`, invokes the allocator, and can rewrite MachV
operands to physical registers plus spill/reload code.

## Example: project MachV into the generic allocator

Projection is a useful debugging step because it lets you inspect the pure
allocation problem before mutating the MachV function.

```moonbit check
///|
test "project a MachV copy into a regalloc program" {
  let func = @machv.AbstractFunction::new("copy")
  let entry = func.new_block()
  let src = func.new_vreg(Int)
  let dst = func.new_vreg(Int)
  let mov = func.new_inst(Move)
  mov.add_operand(@machv.Operand::use_reg(Virtual(src)))
  mov.add_operand(@machv.Operand::def(Virtual(dst)))
  entry.append(mov)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let program = project_function(func, [p0, p1])
  inspect(program.blocks.length(), content="1")
  inspect(program.physical_regs.length(), content="2")
}
```

## Example: allocate and apply the result

`allocate_and_apply_linear_scan` is convenient for tests and simple pipelines:
it allocates, rewrites virtual operands, and materializes spill slots.

```moonbit check
///|
test "rewrite virtual operands to physical registers" {
  let func = @machv.AbstractFunction::new("rewrite")
  let entry = func.new_block()
  let src = func.new_vreg(Int)
  let dst = func.new_vreg(Int)
  let mov = func.new_inst(Move)
  mov.add_operand(@machv.Operand::use_reg(Virtual(src)))
  mov.add_operand(@machv.Operand::def(Virtual(dst)))
  entry.append(mov)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let result = allocate_and_apply_linear_scan(func, [p0, p1])
  inspect(result.allocation.spill_count, content="0")
  inspect(entry.instructions[0].operands[0].reg is Physical(_), content="true")
  inspect(entry.instructions[0].operands[1].reg is Physical(_), content="true")
}
```

## Boundary

This module may depend on MachV and regalloc, but should not depend on Wasmoon
runtime packages or native embedding details.
