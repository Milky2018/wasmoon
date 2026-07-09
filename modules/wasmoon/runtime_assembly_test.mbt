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
  inspect(assembly.machv_function.get_blocks().length(), content="1")
  inspect(assembly.allocated_function.get_blocks().length(), content="1")
  inspect(assembly.code_object.get_bytes().length() > 0, content="true")
  inspect(assembly.x64_abi.pointer_size, content="8")
  inspect(assembly.aarch64_abi.pointer_size, content="8")
  inspect(assembly.jit_glue.length(), content="9")
  inspect(
    @wasmoon_jit.native_glue_covers_jit_ffi_stubs(glue=assembly.jit_glue),
    content="true",
  )
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
    hidden_context_type=None,
  )
  let plan = try! plan_wasm_function_with_compiler_infra(env, mod_, 0, X64)
  inspect(plan.entry_symbol, content="wasm_func_0")
  inspect(plan.object.get_bytes().length() > 0, content="true")
}
