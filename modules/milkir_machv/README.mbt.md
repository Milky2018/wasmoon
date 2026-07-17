# milkir_machv

Verified lowering from MilkIR into target-neutral semantic MachV.

The package preserves typed SSA values, block parameters and edge arguments,
semantic calls, memory effects, traps, safepoints, and source locations. It
does not choose AArch64 or x64 instructions, assign physical registers, lay out
stack frames, or resolve embedding runtime addresses.

## Core lowering

Use `lower_core_function` for MilkIR without extension operations.

```moonbit check
///|
test "lower core MilkIR into semantic MachV" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("add64")
  let left = builder.add_param(I64)
  let right = builder.add_param(I64)
  builder.add_result(I64)
  builder.return_([builder.iadd(left, right)])
  inspect(
    lower_core_function(builder.finalize()),
    content=(
      #|machv add64 [internal](v0:i64, v1:i64) -> (i64) {
      #|block0:
      #|  v2:i64 = int.binary.Add v0, v1
      #|  return v2
      #|}
    ),
  )
}
```

Core lowering verifies its input and rejects unresolved extension operations.
`lower_core_function_with_protocol` additionally lets an embedding state
whether the enclosing function uses the internal or platform call protocol.

## Dialect lowering

`lower_dialect_function` accepts one named dialect, its instruction validator,
explicit environment parameters, and a narrow `InstructionContext` adapter.
The adapter can only construct verified semantic MachV operations and must
complete the declared result contract for every extension instruction.

WebAssembly uses the separate `Milky2018/wasm_machv` package. Product-specific
VMContext offsets, runtime helper names, trap payloads, and executable-memory
integration remain outside this reusable module.
