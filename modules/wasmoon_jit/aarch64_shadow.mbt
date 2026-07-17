///|
fn aarch64_shadow_enabled() -> Bool {
  @sys.get_env_var("WASMOON_AARCH64_SHADOW") == Some("1")
}

///|
fn aarch64_shadow_context(
  function : @semantic_machv.Function,
  environment_field_path : ((@semantic_machv.EnvironmentField) -> Array[Int]?)?,
) -> @aarch64_target.LoweringContext raise JitPipelineError {
  let abi = @aarch64_target.InternalAbi::new(
    0,
    8,
    [1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 1, 2, 3, 4, 5, 6, 7],
  ) catch {
    error =>
      raise PipelineFailure(
        message="\{function.name()}: invalid AArch64 shadow ABI: \{error.to_string()}",
      )
  }
  let mut context = @aarch64_target.LoweringContext::new(abi)
  for block in function.blocks() {
    for instruction in function.block_instructions(block) {
      if function.instruction_operation(instruction)
        is Some(EnvironmentField(field)) {
        guard environment_field_path is Some(resolve) &&
          resolve(field) is Some(offsets) else {
          raise PipelineFailure(
            message="\{function.name()}: missing AArch64 shadow binding for environment field '\{field.name}'",
          )
        }
        context = context.with_environment_field(field, offsets)
      }
    }
  }
  context
}

///|
fn build_aarch64_shadow(
  function : @semantic_machv.Function,
  environment_field_path? : (@semantic_machv.EnvironmentField) -> Array[Int]?,
  allocation_symbols? : Array[@semantic_machv.ExternalSymbol] = [],
  root_scope_symbols? : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  ),
) -> @code_object.UnlinkedCodeObject raise JitPipelineError {
  let elaborated = match root_scope_symbols {
    Some(symbols) =>
      elaborate_wasmoon_runtime_abi(function, allocation_symbols, symbols)
    None => function
  }
  let context = aarch64_shadow_context(elaborated, environment_field_path)
  let selected = @aarch64_target.lower(elaborated, context) catch {
    error =>
      raise PipelineFailure(
        message="\{function.name()}: AArch64 shadow selection failed: \{error.to_string()}",
      )
  }
  let allocation = @aarch64_target.allocate(selected) catch {
    error =>
      raise PipelineFailure(
        message="\{function.name()}: AArch64 shadow allocation failed: \{error.to_string()}",
      )
  }
  let frame = @aarch64_target.plan_frame(selected, allocation) catch {
    error =>
      raise PipelineFailure(
        message="\{function.name()}: AArch64 shadow frame planning failed: \{error.to_string()}",
      )
  }
  @aarch64_target.emit(selected, allocation, frame) catch {
    error =>
      raise PipelineFailure(
        message="\{function.name()}: AArch64 shadow emission failed: \{error.to_string()}",
      )
  }
}
