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
) -> @code_object.UnlinkedCodeObject raise JitPipelineError {
  let context = aarch64_shadow_context(function, environment_field_path)
  let selected = @aarch64_target.lower(function, context) catch {
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

///|
fn compile_aarch64_shadow(
  function : @semantic_machv.Function,
  environment_field_path? : (@semantic_machv.EnvironmentField) -> Array[Int]?,
) -> Unit raise JitPipelineError {
  build_aarch64_shadow(function, environment_field_path?) |> ignore
}

///|
fn maybe_compile_aarch64_shadow(
  function : @semantic_machv.Function,
  isa : @isa.ISA,
  environment_field_path? : (@semantic_machv.EnvironmentField) -> Array[Int]?,
) -> Unit raise JitPipelineError {
  match isa {
    AArch64 if aarch64_shadow_enabled() =>
      compile_aarch64_shadow(function, environment_field_path?)
    _ => ()
  }
}
