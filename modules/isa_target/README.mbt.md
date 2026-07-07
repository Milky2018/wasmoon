# isa_target

Generic ISA lowering from MilkIR to MachV.

This module contains reusable lowering infrastructure shared by concrete
machine targets. It translates `Milky2018/milkir` functions into
`Milky2018/machv` virtual-register machine functions, with target-specific
details supplied by target modules.

## Packages

- `Milky2018/isa_target/lower`: core lowering pipeline from MilkIR to MachV.
- `Milky2018/isa_target/lower/peephole`: post-lowering machine-level cleanup
  and peephole utilities.

## Module-root README tests

This module root exists to document the lowering family. The executable package
is `Milky2018/isa_target/lower`, so `README.mbt.md` examples run through the
root facade package in this directory.

## Example: lower MilkIR with an explicit ISA

`lower_function` converts a verified MilkIR function into a MachV function.
Pass the target ISA explicitly; reusable infrastructure should not detect the
host architecture on its own.

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
  let builder = @milkir.IRBuilder::new("leaf")
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  builder.return_([])
  let lowered = @lower.lower_function(
    builder.get_function(),
    isa=AArch64,
    call_conv_layout=Some(readme_call_conv()),
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
  let builder = @milkir.IRBuilder::new("empty_return")
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  builder.return_([])
  let lowered = @lower.lower_function(
    builder.get_function(),
    isa=AMD64,
    call_conv_layout=Some(readme_call_conv()),
  )
  @lower.optimize_vcode(lowered, isa=AMD64)
  inspect(lowered.get_blocks().length(), content="1")
  inspect(lowered.print().contains("return"), content="true")
}
```

## Boundary

`isa_target` is compiler infrastructure. It should not own embedding-specific
runtime helper addresses, Wasmoon host functions, or native FFI resolution.
Dialect-specific `ExtOp` lowering is supplied by callers through
`lower_function`'s `extension_lowerer` hook plus an explicit runtime-helper
symbol map. WebAssembly uses the separate `Milky2018/wasm_isa_lower` adapter for
that boundary; generic ISA lowering treats unknown extensions as unsupported
instead of decoding Wasm opcodes itself.
