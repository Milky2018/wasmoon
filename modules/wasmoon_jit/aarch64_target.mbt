///|
priv struct AArch64TargetCompilation {
  object : @code_object.UnlinkedCodeObject
  frame_size : Int
}

///|
fn default_aarch64_context() -> @aarch64_target.LoweringContext raise JitPipelineError {
  let abi = @aarch64_target.InternalAbi::new(
    0,
    8,
    [1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
  ) catch {
    error => raise AArch64AbiInvalid(cause=error)
  }
  @aarch64_target.LoweringContext::new(abi)
}
