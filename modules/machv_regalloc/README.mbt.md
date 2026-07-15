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
the target-independent allocator. This package keeps MachV as the machine IR,
invokes the allocator, and returns either a rewritten function or a
Cranelift-style allocation `Output` that the emitter can consume without
mutating the original virtual-register instructions.

## Example: allocate a MachV function

Callers provide their calling-convention data explicitly, allowing the same
allocation workflow to support different ABIs and reserved-register policies.

```moonbit check
///|
fn example_abi() -> @abi.EmbeddingABI {
  let call_conv : @abi.CallConventionLayout = {
    context_arg: { index: 27, class: Int },
    user_arg_gprs: [{ index: 0, class: Int }, { index: 1, class: Int }],
    arg_fprs: [{ index: 0, class: Float64 }, { index: 1, class: Float64 }],
    ret_gprs: [{ index: 0, class: Int }],
    ret_fprs: [{ index: 0, class: Float64 }],
  }
  EmbeddingABI(call_conv, reserve_context_role=false)
}

///|
test "allocate a MachV copy" {
  let builder = @machv.FunctionBuilder::FunctionBuilder("copy")
  let src = builder.add_param(Int)
  builder.add_result(I64)
  let dst = builder.new_vreg(Int)
  builder.append(Move, uses=[Virtual(src)], defs=[{ reg: Virtual(dst) }])
  |> ignore
  builder.terminate(Return([Virtual(dst)]))
  let allocated = allocate_registers_backtracking_with_isa(
    builder.finish(),
    AArch64,
    embedding_abi=Some(example_abi()),
  )
  inspect(allocated.blocks.length(), content="1")
  inspect(allocated.blocks[0].terminator is Some(Return(_)), content="true")
}
```

## Example: consume Cranelift-style output

The output API records per-operand locations and inserted edits. This is the
preferred path for emitters that materialize moves while encoding instructions.

```moonbit check
///|
test "read operand locations from regalloc output" {
  let builder = @machv.FunctionBuilder::FunctionBuilder("rewrite")
  let src = builder.add_param(Int)
  builder.add_result(I64)
  let dst = builder.new_vreg(Int)
  builder.append(Move, uses=[Virtual(src)], defs=[{ reg: Virtual(dst) }])
  |> ignore
  builder.terminate(Return([Virtual(dst)]))
  let (_func, output) = allocate_registers_backtracking_output_with_isa(
    builder.finish(),
    AArch64,
    embedding_abi=Some(example_abi()),
  )
  inspect(output.get_num_spillslots(), content="0")
  inspect(output.inst_def_loc(0, 0, false, 0) is Reg(_), content="true")
  inspect(output.inst_use_loc(0, 0, false, 0) is Reg(_), content="true")
}
```

## Integration

This package translates MachV functions into the `regalloc` input model and
maps allocation results back to MachV locations and edits. Use the rewritten
function API when later passes expect assigned registers, or consume `Output`
directly while emitting instructions.
