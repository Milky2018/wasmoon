# x64_target

x64 target support for MilkIR-to-MachV lowering.

This module provides x86-64 ABI policy, machine-environment construction, and
target lowering hooks used by the generic MilkIR-to-MachV lowering pipeline.

## Package

- `Milky2018/x64_target`: x64 target descriptor, ABI policy, machine
  environment, and lowering entry points.

## When to use it

Use this module when you want x86-64 target policy: System V register
assignment, callee-saved sets, allocatable registers, and convenience lowering
from MilkIR to MachV.

## Example: inspect System V policy

The target API exposes the ABI details a compiler backend needs before
register allocation and emission.

```moonbit check
///|
test "inspect x64 ABI policy" {
  let abi = abi_policy()
  inspect(abi.pointer_size, content="8")
  inspect(abi.stack_alignment, content="16")
  inspect(abi.int_argument_regs.length(), content="6")
  inspect(abi.float_argument_regs.length(), content="8")
}
```

## Example: lower MilkIR through the x64 target

The wrapper returns a MachV function whose target identity is bound to AMD64,
with x64-specific instruction choices and ABI locations.

```moonbit check
///|
test "lower an integer add function for x64" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("add64")
  let lhs = builder.add_param(I64)
  let rhs = builder.add_param(I64)
  builder.add_result(I64)
  builder.return_([builder.iadd(lhs, rhs)])
  let lowered = lower_function(builder.get_function())
  debug_inspect(lowered.target(), content="AMD64")
  inspect(lowered.name, content="add64")
  inspect(lowered.blocks.length(), content="1")
  inspect(
    lowered.blocks[0].insts.any(fn(inst) { inst.opcode is Add(_) }),
    content="true",
  )
}
```

## Example: lower with a custom call convention

Embedders that use their own context register and argument order can pass an
explicit call-convention layout.

```moonbit check
///|
test "lower x64 with an explicit call convention" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("custom_add64")
  let context = builder.add_param(Ptr)
  let lhs = builder.add_param(I64)
  let rhs = builder.add_param(I64)
  builder.add_result(I64)
  builder.return_([builder.iadd(lhs, rhs)])
  context |> ignore
  let conv : @abi.CallConventionLayout = {
    context_arg: { index: 7, class: Int },
    user_arg_gprs: [{ index: 6, class: Int }, { index: 2, class: Int }],
    arg_fprs: [],
    ret_gprs: [{ index: 0, class: Int }],
    ret_fprs: [],
  }
  let lowered = lower_function_with_call_conv(builder.get_function(), conv)
  inspect(lowered.name, content="custom_add64")
  inspect(lowered.blocks.length(), content="1")
}
```

## Integration

Use this package with `Milky2018/milkir_machv` for x64 instruction selection
and `Milky2018/machv_emit` for final machine-code emission. Runtime symbols and
executable-memory allocation are supplied by the embedding application after
emission.
