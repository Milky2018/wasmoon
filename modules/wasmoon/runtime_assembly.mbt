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
  product_support_modules : Array[String]
  reusable_modules : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct CompilerInfrastructureAssembly {
  signature : @milkir.Signature
  machv_function : @machv.Function
  allocated_function : @machv.Function
  code_object : @machv_emit.MachineCode
  x64_abi : @x64_target.AbiPolicy
  aarch64_abi : @aarch64_target.AbiPolicy
  jit_glue : Array[@wasmoon_jit.NativeGlueBinding]
}

///|
pub suberror WasmCompilerPipelineError {
  WasmCompilerPipelineFailure(message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for WasmCompilerPipelineError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub fn wasm_frontend_embedding_environment(
  runtime_symbol_prefix? : String = "wasmoon",
  hidden_context_type? : @milkir.Type? = Some(Ptr),
  cancellation_safepoints? : Bool = false,
) -> @wasm_frontend.EmbeddingEnvironment {
  let vm = @wasmoon_jit.vmcontext_layout()
  let memory = @wasmoon_jit.memory_descriptor_layout()
  EmbeddingEnvironment(
    runtime_symbol_prefix~,
    hidden_context_type~,
    runtime_layout=Some({
      memory0_base_offset: vm.memory0_base_offset,
      memory0_size_offset: vm.memory0_size_offset,
      func_table_offset: vm.func_table_offset,
      table0_base_offset: vm.table0_base_offset,
      table0_elements_offset: vm.table0_elements_offset,
      globals_offset: vm.globals_offset,
      tables_offset: vm.tables_offset,
      table_sizes_offset: vm.table_sizes_offset,
      memories_offset: vm.memories_offset,
      pointer_stride: vm.pointer_stride,
      global_value_stride: vm.global_value_stride,
      table_entry_value_offset: vm.table_entry_value_offset,
      table_entry_stride: vm.table_entry_stride,
      func_table_entry_stride: vm.func_table_entry_stride,
    }),
    memory_descriptor_layout=Some({
      base_offset: memory.base_offset,
      current_length_offset: memory.current_length_offset,
    }),
    cancellation_safepoints~,
  )
}

///|
fn wasm_body_embedding_env(
  env : @wasm_frontend.EmbeddingEnvironment,
) -> @wasm_frontend.EmbeddingEnvironment {
  let defaults = wasm_frontend_embedding_environment(
    runtime_symbol_prefix=env.runtime_symbol_prefix,
    cancellation_safepoints=env.cancellation_safepoints(),
  )
  EmbeddingEnvironment(
    runtime_symbol_prefix=env.runtime_symbol_prefix,
    hidden_context_type=Some(env.hidden_context_param().unwrap_or(Ptr)),
    runtime_layout=match env.runtime_layout() {
      Some(layout) => Some(layout)
      None => defaults.runtime_layout()
    },
    memory_descriptor_layout=match env.memory_descriptor_layout() {
      Some(layout) => Some(layout)
      None => defaults.memory_descriptor_layout()
    },
    wasm_runtime_symbols=Some(env.wasm_runtime_symbols()),
    cancellation_safepoints=env.cancellation_safepoints(),
  )
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
    product_support_modules: ["Milky2018/wasmoon_jit"],
    reusable_modules: [
      "Milky2018/wasm_core", "Milky2018/milkir", "Milky2018/machv", "Milky2018/regalloc",
      "Milky2018/machv_regalloc", "Milky2018/machv_emit", "Milky2018/x64_target",
      "Milky2018/aarch64_target",
    ],
  }
}

///|
pub fn compiler_infrastructure_assembly() -> CompilerInfrastructureAssembly {
  let signature = @milkir.Signature::Signature([], [])
  let milk = @milkir.Function::with_signature(
    "wasmoon_runtime_probe", signature,
  )
  let entry = milk.new_block0()
  entry.set_terminator(Return([]))
  let embedding_abi = @wasmoon_jit.wasm_embedding_abi()
  let machv_function = @lower.lower_function(
    milk,
    run_ir_opt=false,
    embedding_abi=Some(embedding_abi),
  )
  let (allocated_function, output) = @machv_regalloc.allocate_registers_backtracking_output(
    machv_function,
    embedding_abi=Some(embedding_abi),
  )
  {
    signature,
    machv_function,
    allocated_function,
    code_object: @machv_emit.emit_function_with_regalloc(
      allocated_function,
      output,
      embedding_abi=Some(embedding_abi),
    ),
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
    let milk = @wasm_frontend.translate_function(
      body_env,
      mod_,
      func_local_idx,
      name="wasm_func_\{func_local_idx}",
    )
    @milkir.optimize_with_level(milk, @milkir.OptLevel::from_int(opt_level))
    |> ignore
    @wasmoon_jit.plan_wasm_body_milkir_integration_for_target(milk, target)
  } catch {
    err => raise WasmCompilerPipelineFailure(message=to_repr(err).to_string())
  }
}
