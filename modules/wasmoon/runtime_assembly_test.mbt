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
  let assembly = try! compiler_infrastructure_assembly()
  inspect(assembly.signature.params.length(), content="0")
  inspect(assembly.regalloc_program.blocks.length(), content="1")
  inspect(assembly.code_object.debug_entries.length(), content="1")
  inspect(assembly.x64_abi.pointer_size, content="8")
  inspect(assembly.aarch64_abi.pointer_size, content="8")
  inspect(assembly.jit_glue.length(), content="6")
}

///|
test "wasmoon plans wasm function through reusable compiler infrastructure" {
  let mod_ = @types.Module::simple(
    [I32, I32],
    [I32],
    [LocalGet(0), LocalGet(1), I32Add],
    "add",
  )
  let env = @wasm_frontend.EmbeddingEnvironment::new()
  let plan = try! plan_wasm_function_with_compiler_infra(env, mod_, 0, X64)
  inspect(plan.entry_symbol, content="wasm_func_0")
  debug_inspect(plan.target, content="X64")
  inspect(plan.object.code.length() > 0, content="true")
  inspect(plan.object.debug_entries.length() > 0, content="true")
}

///|
test "wasmoon planning restores hidden vmctx for wasm body ABI" {
  let mod_ = @types.Module::simple(
    [I64, I64],
    [I64],
    [LocalGet(0), LocalGet(1), I64Add],
    "add64",
  )
  let env = @wasm_frontend.EmbeddingEnvironment::new(hidden_context_type=None)
  let plan = try! plan_wasm_function_with_compiler_infra(env, mod_, 0, X64)
  inspect(plan.entry_symbol, content="wasm_func_0")
  inspect(plan.object.code.length() > 0, content="true")
}
