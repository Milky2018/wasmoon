# machv_regalloc

Target VCode adapter for the reusable register allocator.

`machv_regalloc` bridges `Milky2018/machv/vcode` functions to the
target-independent `Milky2018/regalloc` algorithm. The adapter reads compact
operand and clobber side tables without inspecting target instructions. It
returns a separate Allocation containing value locations, operand locations,
spill and reload edits, edge moves, stack slots, and safepoint root locations.

## Packages

- `Milky2018/machv_regalloc`: Target VCode projection, allocation entry points,
  validation, spill handling, and output construction.
- `Milky2018/machv_regalloc/layout`: block layout utilities for MachV
  functions.

## When to use it

Use `allocate_vcode` after target instruction selection. Callers provide an
explicit set of allocatable registers and spill scratch registers. The result
is verified against fixed and tied operands, clobbers, stack slots, insertion
edits, edge moves, and safepoint roots before it is returned.

## Example

The instruction payload stays opaque to the allocator. In this small example
`Unit` stands in for a target-owned instruction type.

```moonbit check
///|
test "allocate Target VCode" {
  let builder : @vcode.Builder[Unit] = @vcode.Builder::new("copy", [I64])
  let entry = builder.entry_block()
  let source = builder.parameter(0)
  let (_, result) = builder.append_body(
    entry,
    (),
    [@vcode.Input::any(source)],
    [@vcode.Output::any(I64)],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  builder.set_terminator(
    entry,
    (),
    [@vcode.Input::any(result[0])],
    [],
    [],
    @vcode.InstructionMetadata::empty(),
  )
  |> ignore
  let function = builder.finish()
  let allocation = allocate_vcode(
    function,
    VCodeAllocationEnvironment::new([@vcode.PhysicalReg::new(0, Int)], [
      @vcode.PhysicalReg::new(1, Int),
    ]),
  )
  inspect(allocation.source_instruction_count(), content="2")
}
```

## Integration

Each target emitter consumes its unchanged `Function[TargetInst]` together
with the returned Allocation and a verified frame layout. Physical-register
lookups and insertion edits are constant-time or linear side-table queries;
the adapter never introduces runtime dispatch over target instructions.
