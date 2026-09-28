///|
priv struct X64TargetCompilation[T] {
  object : T
  frame_size : Int
}

///|
fn default_x64_context() -> @x64_target.LoweringContext raise JitPipelineError {
  let abi = @x64_target.InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  ) catch {
    error => raise X64AbiInvalid(cause=error)
  }
  @x64_target.LoweringContext::new(abi)
}

///|
fn compile_selected_x64_object(
  selected : @x64_target.SelectedFunction,
  on_event : (@vcode.TargetCompileEvent) -> Unit,
) -> (@code_object.UnlinkedCodeObject, Int) raise @x64_target.X64CompileError {
  @x64_target.compile_selected(
    selected,
    on_event~,
    verify_allocation=compiler_validation(),
  )
}
