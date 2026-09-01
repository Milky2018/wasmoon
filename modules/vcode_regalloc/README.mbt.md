# vcode_regalloc

Target VCode adapter for the reusable register allocator.

`vcode_regalloc` bridges `Milky2018/vcode` functions to the
target-independent `Milky2018/regalloc` algorithm. The adapter reads compact
operand and clobber side tables without inspecting target instructions. It
returns a separate Allocation containing value locations, operand locations,
spill and reload edits, edge moves, stack slots, and safepoint root locations.

## Packages

- `Milky2018/vcode_regalloc`: read-only Target VCode adapter, allocation entry
  points, validation, spill handling, and output construction.

## When to use it

Use `allocate_vcode` after target instruction selection. Callers provide an
explicit set of allocatable registers and spill scratch registers. The result
is verified against fixed and tied operands, clobbers, stack slots, insertion
edits, edge moves, and safepoint roots before it is returned.

The production adapter normalizes Target VCode once into flat tables and offset
vectors, then exposes non-owning `ArrayView` spans through `FunctionView`; it
does not build a second nested instruction or CFG graph. The aggregate target
pipeline can verify selected VCode, run the root bundle-aware allocator,
materialize its `AllocationPlan` into VCode `Allocation` side tables, and then
run the independent VCode allocation verifier. Safe public entry points enable
both the reusable plan verifier and the materialized VCode state verifier; the
latter follows resident values through edits, clobbers, and CFG joins. The
Wasmoon JIT skips these redundant checks for compiler-owned VCode in production
and restores them in strict CI with `VCODE_REGALLOC_VALIDATION=1`. There is no
second backtracking policy package and no alternate allocation strategy.

Ordinary `Input::any` operands require a register at the instruction. A target
operation that can consume a register or spill slot directly uses
`Input::any_location`; its emitter then reads the allocated `Location` without
forcing every such input through a simultaneous scratch-register reload.
`Input::with_preference` may additionally request a same-class allocatable
register without turning that request into a hard constraint. Production call
lowering uses this for ABI argument registers, while the post-allocation call
transfer planner remains responsible for the actual register and stack shuffle.
ABI pseudos that materialize an implicit incoming register or stack value use
`Output::any_location`, so the result is written directly to its stable home.
`Output::with_preference` keeps the move-free incoming-register case cheap when
that register is allocatable, without pinning the value's full live range.

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
