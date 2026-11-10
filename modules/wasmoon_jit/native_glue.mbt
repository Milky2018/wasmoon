///|
/// Stable, read-only renderings of the final native compilation checkpoints.
/// Concrete target instruction, allocation, and frame types remain owned by
/// their target modules and do not cross this diagnostics facade.
#derive(Debug)
pub struct JitPipelineDiagnostics {
  target_vcode : String
  allocated_vcode : String
  code_object : String
  machine_code : String
}

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
#derive(Debug)
pub suberror JitPipelineError {
  NativeLoweringFailed(cause~ : @milkir_native.NativeLowerError)
  AArch64AbiInvalid(cause~ : @aarch64_target.InternalAbiError)
  X64AbiInvalid(cause~ : @x64_target.InternalAbiError)
  AArch64LoweringFailed(cause~ : @aarch64_target.AArch64LowerError)
  X64LoweringFailed(cause~ : @x64_target.X64LowerError)
  AArch64CompilationFailed(cause~ : @aarch64_target.AArch64CompileError)
  X64CompilationFailed(cause~ : @x64_target.X64CompileError)
  UnsupportedHostArchitecture(tag~ : Int32)
  UnsupportedHostOsAbi(tag~ : Int32)
  InvalidFunctionIndex(index~ : Int32)
}

///|
pub impl Show for JitPipelineError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
/// Compile platform-entry MilkIR into a full symbolic code object and frame size.
/// Linking remains owned by the selected target's link plan.
pub fn NativeCompiler::compile_core(
  self : NativeCompiler,
  function : @milkir.Function,
) -> (@code_object.UnlinkedCodeObject, Int32) raise JitPipelineError {
  let signature = @milkir_native.function_signature(function)
  let context = native_lowering_context(self.backend.target())
  self.backend.compile(function.name, Platform, signature, context, sink => {
    @milkir_native.lower_core_to_sink(function, sink) catch {
      error => raise NativeLoweringFailed(cause=error)
    }
  })
}
