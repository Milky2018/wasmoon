///|
test "wasmoon remains the product runtime module" {
  let assembly = runtime_assembly()
  inspect(assembly.product_module, content="Milky2018/wasmoon")
  inspect(
    assembly.owned_components.contains(InterpreterExecutor),
    content="true",
  )
  inspect(assembly.owned_components.contains(Cli), content="true")
  inspect(
    assembly.reusable_modules.contains("Milky2018/wasmoon_runtime"),
    content="false",
  )
}

///|
test "wasmoon consumes reusable compiler infrastructure" {
  let assembly = compiler_infrastructure_assembly()
  inspect(assembly.signature.params.length(), content="0")
  inspect(assembly.regalloc_program.blocks.length(), content="1")
  inspect(assembly.code_object.debug_entries.length(), content="1")
  inspect(assembly.x64_abi.pointer_size, content="8")
  inspect(assembly.aarch64_abi.pointer_size, content="8")
  inspect(assembly.jit_glue.length(), content="6")
}
