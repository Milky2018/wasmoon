///|
pub(all) struct JitIntegrationPlan {
  entry_symbol : String
  target : NativeTarget
  object : JitCodeObject
}

///|
/// Stable, read-only renderings of the final native compilation checkpoints.
/// Concrete target instruction, allocation, and frame types remain owned by
/// their target modules and do not cross this diagnostics facade.
pub struct JitPipelineDiagnostics {
  semantic_machv : String
  target_vcode : String
  allocated_vcode : String
  code_object : String
  machine_code : String
} derive(Debug)

///|
fn code_object_diagnostic_text(
  object : @code_object.UnlinkedCodeObject,
) -> String {
  let architecture = match object.architecture() {
    AArch64 => "aarch64"
    X64 => "x64"
  }
  let code = object.code()
  let bytes = code.map(byte => @types.to_hex_byte(byte.to_int())).join(" ")
  "code-object \{architecture}\n" +
  "  code-size: \{code.length()}\n" +
  "  relocations: \{Repr(object.relocations())}\n" +
  "  sources: \{Repr(object.sources())}\n" +
  "  traps: \{Repr(object.traps())}\n" +
  "  safepoints: \{Repr(object.safepoints())}\n" +
  "  unwind: \{Repr(object.unwind())}\n" +
  "  bytes: \{bytes}"
}

///|
pub suberror JitPipelineError {
  SemanticLoweringFailed(cause~ : @milkir_machv.SemanticLowerError)
  RuntimeAbiInputInvalid(cause~ : @semantic_machv.MachVVerifyError)
  RuntimeAbiOutputInvalid(cause~ : @semantic_machv.MachVVerifyError)
  RuntimeAbiContractViolation(message~ : String)
  AArch64AbiInvalid(cause~ : @aarch64_target.InternalAbiError)
  X64AbiInvalid(cause~ : @x64_target.InternalAbiError)
  MissingEnvironmentField(target~ : NativeTarget, field~ : String)
  AArch64LoweringFailed(cause~ : @aarch64_target.AArch64LowerError)
  X64LoweringFailed(cause~ : @x64_target.X64LowerError)
  AArch64CompilationFailed(cause~ : @aarch64_target.AArch64CompileError)
  X64CompilationFailed(cause~ : @x64_target.X64CompileError)
  AArch64AllocationFailed(cause~ : @aarch64_target.AArch64AllocationError)
  X64AllocationFailed(cause~ : @x64_target.X64AllocationError)
  AArch64FramePlanningFailed(cause~ : @aarch64_target.AArch64FrameError)
  X64FramePlanningFailed(cause~ : @x64_target.X64FrameError)
  AArch64EmissionFailed(cause~ : @aarch64_target.AArch64EmitError)
  X64EmissionFailed(cause~ : @x64_target.X64EmitError)
  AArch64LinkPreparationFailed(cause~ : @aarch64_target.AArch64LinkError)
  X64LinkPreparationFailed(cause~ : @x64_target.X64LinkError)
  InvalidJitRelocation(target~ : NativeTarget, index~ : Int, message~ : String)
  UnsupportedEntrySignature(message~ : String)
  UnsupportedHostArchitecture(tag~ : Int)
  UnsupportedHostOsAbi(tag~ : Int)
  InvalidFunctionIndex(index~ : Int)
} derive(Debug)

///|
pub impl Show for JitPipelineError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
pub fn plan_milkir_integration_for_target(
  func : @milkir.Function,
  target : NativeTarget,
) -> JitIntegrationPlan raise JitPipelineError {
  if target is AArch64 {
    let semantic = @milkir_machv.lower_core_function_with_protocol(
      func,
      Platform,
    ) catch {
      error => raise SemanticLoweringFailed(cause=error)
    }
    let compiled = build_aarch64_target(semantic)
    return {
      entry_symbol: func.name,
      target,
      object: jit_code_object_from_aarch64(compiled.object, compiled.frame_size),
    }
  }
  let semantic = @milkir_machv.lower_core_prepared_selection_with_protocol(
    func,
    Platform,
  ) catch {
    error => raise SemanticLoweringFailed(cause=error)
  }
  let compiled = build_x64_target(semantic)
  return {
    entry_symbol: func.name,
    target,
    object: jit_code_object_from_x64(compiled.object, compiled.frame_size),
  }
}

///|
pub fn plan_wasm_body_milkir_integration_for_target(
  func : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  target : NativeTarget,
) -> JitIntegrationPlan raise JitPipelineError {
  if target is AArch64 {
    let compiled = compile_wasm_body_aarch64_target(
      func,
      validation_context,
      true,
      [],
    )
    return {
      entry_symbol: func.name,
      target,
      object: jit_code_object_from_aarch64(compiled.object, compiled.frame_size),
    }
  }
  let compiled = compile_wasm_body_x64_target(func, validation_context, true, [])
  {
    entry_symbol: func.name,
    target,
    object: jit_code_object_from_x64(compiled.object, compiled.frame_size),
  }
}
