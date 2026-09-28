///|
priv struct AArch64TargetCompilation[T] {
  object : T
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

///|
fn compile_selected_aarch64_object(
  selected : @aarch64_target.SelectedFunction,
  on_event : (@vcode.TargetCompileEvent) -> Unit,
) -> (@code_object.UnlinkedCodeObject, Int) raise @aarch64_target.AArch64CompileError {
  @aarch64_target.compile_selected(
    selected,
    on_event~,
    verify_allocation=compiler_validation(),
  )
}
