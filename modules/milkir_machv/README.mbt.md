# milkir_machv

Generic MilkIR-to-MachV lowering.

This module contains reusable lowering infrastructure shared by concrete
machine targets. It translates `Milky2018/milkir` functions into
`Milky2018/machv` virtual-register machine functions, with target-specific
details supplied by target modules.

## Packages

- `Milky2018/milkir_machv/lower`: core lowering pipeline from MilkIR to MachV.
- `Milky2018/milkir_machv/lower/peephole`: post-lowering machine-level cleanup
  and peephole utilities.

## Example: lower MilkIR with an explicit config

`LoweringConfig` groups the target and lowering policy for user-facing code.
Passing the target ISA explicitly supports cross-target compilation and makes
tests independent of the host architecture. Config methods provide additional
hooks for dialect and embedding-specific lowering.

```moonbit check
///|
fn readme_call_conv() -> @abi.CallConventionLayout {
  {
    context_arg: { index: 0, class: Int },
    user_arg_gprs: [{ index: 1, class: Int }, { index: 2, class: Int }],
    arg_fprs: [],
    ret_gprs: [{ index: 0, class: Int }],
    ret_fprs: [],
  }
}

///|
test "lower a leaf MilkIR function to AArch64 MachV" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("leaf")
  builder.return_([])
  let config = @lower.LoweringConfig(AArch64).with_embedding_abi(
    EmbeddingABI(readme_call_conv()),
  )
  let lowered = @lower.lower_function_with_config(
    builder.get_function(),
    config,
  )
  inspect(lowered.get_name(), content="leaf")
  inspect(lowered.get_blocks().length(), content="1")
  inspect(lowered.has_calls(), content="false")
}
```

## Example: run post-lowering cleanup

The lowering package also exposes peephole cleanup for callers that construct or
modify MachV directly.

```moonbit check
///|
test "optimize an explicitly targeted MachV function" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("empty_return")
  builder.return_([])
  let config = @lower.LoweringConfig(AMD64).with_embedding_abi(
    EmbeddingABI(readme_call_conv()),
  )
  let lowered = @lower.lower_function_with_config(
    builder.get_function(),
    config,
  )
  @lower.optimize_machv(lowered, isa=AMD64)
  inspect(lowered.get_blocks().length(), content="1")
  inspect(lowered.print().contains("return"), content="true")
}
```

## Extension lowering

Dialect-specific `ExtOp` lowering is supplied through
`LoweringConfig::with_extension_lowerer` plus an explicit runtime-helper symbol
map. WebAssembly callers can use the `Milky2018/wasm_isa_lower` adapter. An
extension without a configured lowerer is reported as unsupported.
