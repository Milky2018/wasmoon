///|
pub(all) enum RuntimeComponent {
  Cli
  RuntimeObjects
  InterpreterExecutor
  WasiPreview1
  JitSelection
} derive(Eq, Debug)

///|
pub(all) struct RuntimeAssembly {
  product_module : String
  owned_components : Array[RuntimeComponent]
  reusable_modules : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct CompilerInfrastructureAssembly {
  signature : @milkir.Signature
  machv_function : @machv.Function
  regalloc_program : @regalloc.Program
  code_object : @machv_emit.CodeObject
  x64_abi : @x64_target.AbiPolicy
  aarch64_abi : @aarch64_target.AbiPolicy
  jit_glue : Array[@wasmoon_jit.NativeGlueBinding]
} derive(Debug)

///|
pub suberror WasmCompilerPipelineError {
  WasmCompilerPipelineFailure(message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for WasmCompilerPipelineError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn wasm_body_embedding_env(
  env : @wasm_frontend.EmbeddingEnvironment,
) -> @wasm_frontend.EmbeddingEnvironment {
  if env.hidden_context_param() is Some(_) {
    env
  } else {
    @wasm_frontend.EmbeddingEnvironment::new(
      runtime_symbol_prefix=env.runtime_symbol_prefix,
    )
  }
}

///|
pub fn runtime_assembly() -> RuntimeAssembly {
  {
    product_module: "Milky2018/wasmoon",
    owned_components: [
      Cli,
      RuntimeObjects,
      InterpreterExecutor,
      WasiPreview1,
      JitSelection,
    ],
    reusable_modules: [
      "Milky2018/wasm_core", "Milky2018/milkir", "Milky2018/machv", "Milky2018/regalloc",
      "Milky2018/machv_regalloc", "Milky2018/machv_emit", "Milky2018/x64_target",
      "Milky2018/aarch64_target", "Milky2018/wasmoon_jit",
    ],
  }
}

///|
pub fn compiler_infrastructure_assembly() -> CompilerInfrastructureAssembly raise @machv_emit.EmitError {
  let signature = @milkir.Signature::new([], [])
  let machv_function = @machv.Function::new("wasmoon_runtime_probe")
  let entry = machv_function.new_block()
  entry.append(machv_function.new_inst(Return))
  let x64_regs = @x64_target.allocatable_regs()
  {
    signature,
    machv_function,
    regalloc_program: @machv_regalloc.project_function(machv_function, x64_regs),
    code_object: @machv_emit.emit_function_for_target(machv_function, AArch64),
    x64_abi: @x64_target.abi_policy(),
    aarch64_abi: @aarch64_target.abi_policy(),
    jit_glue: @wasmoon_jit.default_native_glue(),
  }
}

///|
pub fn plan_wasm_function_with_compiler_infra(
  env : @wasm_frontend.EmbeddingEnvironment,
  mod_ : @types.Module,
  func_local_idx : Int,
  target : @machv_emit.EmitTarget,
  opt_level? : Int = 2,
) -> @wasmoon_jit.JitIntegrationPlan raise WasmCompilerPipelineError {
  try {
    let body_env = wasm_body_embedding_env(env)
    let milk = @wasm_frontend.lower_function(body_env, mod_, func_local_idx)
    @milkir.optimize_with_level(milk, @milkir.OptLevel::from_int(opt_level))
    |> ignore
    @wasmoon_jit.plan_wasm_body_milkir_integration_for_target(milk, target)
  } catch {
    err => raise WasmCompilerPipelineFailure(message=to_repr(err).to_string())
  }
}
