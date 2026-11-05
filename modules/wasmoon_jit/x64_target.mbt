///|
priv struct X64TargetCompilation {
  object : @code_object.UnlinkedCodeObject
  frame_size : Int32
}

///|
fn default_x64_context() -> @x64_target.LoweringContext raise JitPipelineError {
  let abi = wasm_internal_abi(X64) catch {
    error => raise X64AbiInvalid(cause=error)
  }
  @x64_target.LoweringContext::new(abi)
}
