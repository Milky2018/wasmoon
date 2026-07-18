///|
priv struct X64TargetCompilation {
  object : @code_object.UnlinkedCodeObject
  frame_size : Int
}

///|
fn x64_target_context(
  function : @semantic_machv.Function,
  environment_field_path : ((@semantic_machv.EnvironmentField) -> Array[Int]?)?,
) -> @x64_target.LoweringContext raise JitPipelineError {
  let abi = @x64_target.InternalAbi::new(
    7,
    12,
    [6, 2, 1, 8, 9],
    [0, 1, 2, 3, 4, 5, 6, 7],
    [0, 2, 1, 8, 9, 6, 7, 10],
    [0, 1, 2, 3, 4, 5, 6, 7],
  ) catch {
    error =>
      raise PipelineFailure(
        message="\{function.name()}: invalid x64 ABI: \{error.to_string()}",
      )
  }
  let mut context = @x64_target.LoweringContext::new(abi)
  for block in function.blocks() {
    for instruction in function.block_instructions(block) {
      if function.instruction_operation(instruction)
        is Some(EnvironmentField(field)) {
        guard environment_field_path is Some(resolve) &&
          resolve(field) is Some(offsets) else {
          raise PipelineFailure(
            message="\{function.name()}: missing x64 binding for environment field '\{field.name}'",
          )
        }
        context = context.with_environment_field(field, offsets)
      }
    }
  }
  context
}

///|
fn build_x64_target(
  function : @semantic_machv.Function,
  environment_field_path? : (@semantic_machv.EnvironmentField) -> Array[Int]?,
  allocation_symbols? : Array[@semantic_machv.ExternalSymbol] = [],
  root_scope_symbols? : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  ),
) -> X64TargetCompilation raise JitPipelineError {
  let elaborated = match root_scope_symbols {
    Some(symbols) =>
      elaborate_wasmoon_runtime_abi(function, allocation_symbols, symbols)
    None => function
  }
  let context = x64_target_context(elaborated, environment_field_path)
  let selected = @x64_target.lower(elaborated, context) catch {
    error =>
      raise PipelineFailure(
        message="\{function.name()}: x64 selection failed: \{error.to_string()}",
      )
  }
  let allocation = @x64_target.allocate(selected) catch {
    error =>
      raise PipelineFailure(
        message="\{function.name()}: x64 allocation failed: \{error.to_string()}",
      )
  }
  let frame = @x64_target.plan_frame(selected, allocation) catch {
    error =>
      raise PipelineFailure(
        message="\{function.name()}: x64 frame planning failed: \{error.to_string()}",
      )
  }
  let object = @x64_target.emit(selected, allocation, frame) catch {
    error =>
      raise PipelineFailure(
        message="\{function.name()}: x64 emission failed: \{error.to_string()}",
      )
  }
  { object, frame_size: frame.frame_size() }
}
