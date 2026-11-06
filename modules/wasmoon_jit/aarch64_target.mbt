///|
priv struct AArch64TargetCompilation {
  object : @code_object.UnlinkedCodeObject
  frame_size : Int32
}

///|
fn default_aarch64_context() -> @aarch64_target.LoweringContext raise JitPipelineError {
  let abi = wasm_internal_abi(AArch64) catch {
    error => raise AArch64AbiInvalid(cause=error)
  }
  @aarch64_target.LoweringContext::new(abi)
}
