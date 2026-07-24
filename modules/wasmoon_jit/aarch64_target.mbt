///|
priv struct AArch64TargetCompilation {
  object : @code_object.UnlinkedCodeObject
  frame_size : Int
}

///|
priv struct AArch64TargetDiagnostics {
  target_vcode : String
  allocated_vcode : String
  object : @code_object.UnlinkedCodeObject
}

///|
fn aarch64_target_context(
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
    error => raise AArch64AbiInvalid(cause=error)
  }
  let mut context = @aarch64_target.LoweringContext::new(abi)
  for block in function.blocks() {
    for instruction in function.block_instructions(block) {
      if function.instruction_operation(instruction)
        is Some(EnvironmentField(field, _)) {
        guard environment_field_path is Some(resolve) &&
          resolve(field) is Some(offsets) else {
          raise MissingEnvironmentField(target=AArch64, field=field.name)
        }
        context = context.with_environment_field(field, offsets)
      }
    }
  }
  context
}

///|
fn build_aarch64_target(
  function : @semantic_machv.Function,
  environment_field_path? : (@semantic_machv.EnvironmentField) -> Array[Int]?,
  allocation_symbols? : Array[@semantic_machv.ExternalSymbol] = [],
  record_metrics? : Bool = false,
  root_scope_symbols? : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  ),
) -> AArch64TargetCompilation raise JitPipelineError {
  let target_lower_tick = target_metrics_tick(record_metrics)
  let elaborated = match root_scope_symbols {
    Some(symbols) =>
      elaborate_wasmoon_runtime_abi(function, allocation_symbols, symbols)
    None => function
  }
  let context = aarch64_target_context(elaborated, environment_field_path)
  let selected = @aarch64_target.lower(elaborated, context) catch {
    error => raise AArch64LoweringFailed(cause=error)
  }
  let compiled = try {
    match target_lower_tick {
      Some(tick) =>
        @aarch64_target.compile(
          selected,
          on_event=target_compile_metrics_observer(tick),
        )
      None => @aarch64_target.compile(selected)
    }
  } catch {
    error => raise AArch64CompilationFailed(cause=error)
  }
  let (object, frame_size) = compiled
  { object, frame_size }
}

///|
fn diagnose_aarch64_target(
  function : @semantic_machv.Function,
  environment_field_path? : (@semantic_machv.EnvironmentField) -> Array[Int]?,
  allocation_symbols? : Array[@semantic_machv.ExternalSymbol] = [],
  root_scope_symbols? : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  ),
) -> AArch64TargetDiagnostics raise JitPipelineError {
  let elaborated = match root_scope_symbols {
    Some(symbols) =>
      elaborate_wasmoon_runtime_abi(function, allocation_symbols, symbols)
    None => function
  }
  let context = aarch64_target_context(elaborated, environment_field_path)
  let selected = @aarch64_target.lower(elaborated, context) catch {
    error => raise AArch64LoweringFailed(cause=error)
  }
  let allocation = @aarch64_target.allocate(selected) catch {
    error => raise AArch64AllocationFailed(cause=error)
  }
  let frame = @aarch64_target.plan_frame(selected, allocation) catch {
    error => raise AArch64FramePlanningFailed(cause=error)
  }
  let object = @aarch64_target.emit(selected, allocation, frame) catch {
    error => raise AArch64EmissionFailed(cause=error)
  }
  {
    target_vcode: selected.summary(),
    allocated_vcode: selected.summary() + allocation.summary(),
    object,
  }
}
