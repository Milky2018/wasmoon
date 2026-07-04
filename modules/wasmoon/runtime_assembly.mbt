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
pub fn compiler_infrastructure_assembly() -> CompilerInfrastructureAssembly {
  let signature = @milkir.Signature::new([], [])
  let machv_function = @machv.Function::new("wasmoon_runtime_probe")
  let entry = machv_function.new_block()
  entry.append(machv_function.new_inst(Return))
  let x64_regs = @x64_target.allocatable_regs()
  {
    signature,
    machv_function,
    regalloc_program: @machv_regalloc.project_function(machv_function, x64_regs),
    code_object: @machv_emit.emit_function(machv_function),
    x64_abi: @x64_target.abi_policy(),
    aarch64_abi: @aarch64_target.abi_policy(),
    jit_glue: @wasmoon_jit.default_native_glue(),
  }
}
