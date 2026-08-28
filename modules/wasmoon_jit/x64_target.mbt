///|
priv struct X64TargetCompilation {
  object : @code_object.UnlinkedCodeObject
  frame_size : Int
}

///|
priv struct X64TargetDiagnostics {
  target_vcode : String
  allocated_vcode : String
  object : @code_object.UnlinkedCodeObject
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
    error => raise X64AbiInvalid(cause=error)
  }
  let mut context = @x64_target.LoweringContext::new(abi)
  for block in function.blocks() {
    for instruction in function.block_instructions(block) {
      if function.instruction_operation(instruction)
        is Some(EnvironmentField(field, _)) {
        guard environment_field_path is Some(resolve) &&
          resolve(field) is Some(offsets) else {
          raise MissingEnvironmentField(target=X64, field=field.name)
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
  record_metrics? : Bool = false,
  root_scope_symbols? : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  ),
) -> X64TargetCompilation raise JitPipelineError {
  let target_lower_tick = target_metrics_tick(record_metrics)
  let observer = target_lower_tick.map(target_compile_metrics_observer)
  let runtime_abi_tick = detail_metrics_tick(record_metrics)
  let elaborated = match root_scope_symbols {
    Some(symbols) =>
      elaborate_wasmoon_runtime_abi(function, allocation_symbols, symbols)
    None => function
  }
  record_compile_subphase("runtime_abi_elaboration", runtime_abi_tick)
  let context_tick = detail_metrics_tick(record_metrics)
  let context = x64_target_context(elaborated, environment_field_path)
  record_compile_subphase("target_context", context_tick)
  let selected = try {
    match observer {
      Some(observe) =>
        @x64_target.select_verified(elaborated, context, on_event=observe)
      None => @x64_target.select_verified(elaborated, context)
    }
  } catch {
    error => raise X64LoweringFailed(cause=error)
  }
  let compiled = try {
    match observer {
      Some(observe) =>
        @x64_target.compile_selected(
          selected,
          on_event=observe,
          verify_allocation=regalloc_validation(),
        )
      None =>
        @x64_target.compile_selected(
          selected,
          verify_allocation=regalloc_validation(),
        )
    }
  } catch {
    error => raise X64CompilationFailed(cause=error)
  }
  let (object, frame_size) = compiled
  { object, frame_size, }
}

///|
fn diagnose_x64_target(
  function : @semantic_machv.Function,
  environment_field_path? : (@semantic_machv.EnvironmentField) -> Array[Int]?,
  allocation_symbols? : Array[@semantic_machv.ExternalSymbol] = [],
  root_scope_symbols? : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  ),
) -> X64TargetDiagnostics raise JitPipelineError {
  let elaborated = match root_scope_symbols {
    Some(symbols) =>
      elaborate_wasmoon_runtime_abi(function, allocation_symbols, symbols)
    None => function
  }
  let context = x64_target_context(elaborated, environment_field_path)
  let selected = @x64_target.lower(elaborated, context) catch {
    error => raise X64LoweringFailed(cause=error)
  }
  let allocation = @x64_target.allocate(selected) catch {
    error => raise X64AllocationFailed(cause=error)
  }
  let frame = @x64_target.plan_frame(selected, allocation) catch {
    error => raise X64FramePlanningFailed(cause=error)
  }
  let object = @x64_target.emit(selected, allocation, frame) catch {
    error => raise X64EmissionFailed(cause=error)
  }
  {
    target_vcode: selected.summary(),
    allocated_vcode: selected.summary() + allocation.summary(),
    object,
  }
}
