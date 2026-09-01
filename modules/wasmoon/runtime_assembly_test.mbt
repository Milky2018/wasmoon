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
  inspect(
    assembly.reusable_modules.contains("Milky2018/wasmoon_jit"),
    content="false",
  )
  inspect(
    assembly.product_support_modules.contains("Milky2018/wasmoon_jit"),
    content="true",
  )
  inspect(
    assembly.reusable_modules.contains("Milky2018/milkir"),
    content="true",
  )
  inspect(
    assembly.reusable_modules.contains("Milky2018/wasm_component"),
    content="true",
  )
}

///|
test "wasmoon consumes reusable compiler infrastructure" {
  let assembly = compiler_infrastructure_assembly()
  inspect(assembly.signature.params.length(), content="0")
  inspect(assembly.milkir_function.blocks.length(), content="1")
  inspect(assembly.code_object.get_bytes().length() > 0, content="true")
}

///|
test "wasmoon plans wasm function through reusable compiler infrastructure" {
  let mod_ = @types.Module::simple(
    [I32, I32],
    [I32],
    [LocalGet(0), LocalGet(1), I32Add],
    "add",
  )
  let env = wasm_frontend_embedding_environment()
  let plan = try! plan_wasm_function_with_compiler_infra(env, mod_, 0, X64)
  inspect(plan.entry_symbol, content="wasm_func_0")
  debug_inspect(plan.target, content="X64")
  inspect(plan.object.get_bytes().length() > 0, content="true")
}

///|
test "wasmoon planning restores hidden vmctx for wasm body ABI" {
  let mod_ = @types.Module::simple(
    [I64, I64],
    [I64],
    [LocalGet(0), LocalGet(1), I64Add],
    "add64",
  )
  let env = @wasm_frontend.EmbeddingEnvironment::EmbeddingEnvironment(
    runtime_symbol_prefix="wasmoon",
    hidden_context_type=None,
  )
  let plan = try! plan_wasm_function_with_compiler_infra(env, mod_, 0, X64)
  inspect(plan.entry_symbol, content="wasm_func_0")
  inspect(plan.object.get_bytes().length() > 0, content="true")
}
