///|
priv struct WasmoonNativeEnvironment {
  wasm : @wasm_native.Environment
  field_paths : Map[String, Array[Int]]
  runtime_symbols : @wasm_milkir.RuntimeSymbols
}

///|
fn wasmoon_native_environment(
  use_subtype_indirect_check : Bool,
  canonical_type_indices : Array[Int],
) -> WasmoonNativeEnvironment {
  let layout = vmcontext_layout()
  let field_paths : Map[String, Array[Int]] = Map([])
  let runtime_symbols = wasm_runtime_symbols()
  let function_table_field = @native.EnvironmentField::new(
    "wasmoon.vmctx.function_table",
    Ptr64,
  )
  field_paths.set(function_table_field.name, [layout.func_table_offset])
  let canonical_type_indices = canonical_type_indices.copy()
  let wasm = @wasm_native.Environment::new(
    fn(index) {
      let name = "wasm.func.\{index}"
      @native.CodeSymbol::new(name)
    },
    fn(index) {
      let field = @native.EnvironmentField::new(
        "wasmoon.vmctx.memory.\{index}.base",
        Ptr64,
      )
      let path = if index == 0 {
        [layout.memory0_base_offset]
      } else {
        [layout.memories_offset, index * layout.pointer_stride, 0]
      }
      field_paths.set(field.name, path)
      field
    },
    function_table_field,
    fn(index) {
      let field = @native.EnvironmentField::new(
        "wasmoon.vmctx.table.\{index}.base",
        Ptr64,
      )
      let path = if index == 0 {
        [layout.table0_base_offset]
      } else {
        [layout.tables_offset, index * layout.pointer_stride]
      }
      field_paths.set(field.name, path)
      field
    },
    fn(raw_type_index) {
      if use_subtype_indirect_check {
        return raw_type_index
      }
      if raw_type_index >= 0 && raw_type_index < canonical_type_indices.length() {
        canonical_type_indices[raw_type_index]
      } else {
        raw_type_index
      }
    },
    fn(helper) {
      @native.ExternalSymbol::new(runtime_symbols.symbol_name(helper))
    },
  )
  { wasm, field_paths, runtime_symbols, }
}

///|
fn wasmoon_allocation_symbols(
  environment : WasmoonNativeEnvironment,
) -> Array[@native.ExternalSymbol] {
  [
    @native.ExternalSymbol::new(
      environment.runtime_symbols.symbol_name(GcAllocStructSlow),
    ),
    @native.ExternalSymbol::new(
      environment.runtime_symbols.symbol_name(GcAllocArrayFromValuesSlow),
    ),
    @native.ExternalSymbol::new(
      environment.runtime_symbols.symbol_name(GcAllocArraySlow),
    ),
  ]
}

///|
fn wasmoon_call_abi(
  environment : WasmoonNativeEnvironment,
) -> @native_lowering.CallAbiElaboration {
  let hidden_safepoints : Array[@native_lowering.HiddenSafepointAbi] = []
  for symbol in wasmoon_allocation_symbols(environment) {
    hidden_safepoints.push(
      @native_lowering.HiddenSafepointAbi::new(symbol, AllocationOperands),
    )
  }
  @native_lowering.CallAbiElaboration::new(
    root_scope=@native_lowering.CallerRootScopeAbi::new(
      @native.ExternalSymbol::new(gc_push_root_scope_symbol()),
      @native.ExternalSymbol::new(gc_pop_root_scope_symbol()),
    ),
    hidden_safepoints~,
  )
}

///|
fn wasm_x64_context(
  environment : WasmoonNativeEnvironment,
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
  @x64_target.LoweringContext::new(abi).with_environment_field_resolver(field => {
    environment.field_paths.get(field.name)
  })
}

///|
fn wasm_aarch64_context(
  environment : WasmoonNativeEnvironment,
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
  @aarch64_target.LoweringContext::new(abi).with_environment_field_resolver(field => {
    environment.field_paths.get(field.name)
  })
}

///|
fn compile_wasm_body_x64_target(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  use_subtype_indirect_check : Bool,
  canonical_type_indices : Array[Int],
  record_metrics? : Bool = false,
  compilation_session? : @x64_target.CompilationSession = @x64_target.CompilationSession::new(),
) -> X64TargetCompilation raise JitPipelineError {
  let environment_tick = detail_metrics_tick(record_metrics)
  let environment = wasmoon_native_environment(
    use_subtype_indirect_check, canonical_type_indices,
  )
  let context = wasm_x64_context(environment)
  record_compile_subphase("native_environment", environment_tick)
  let signature = @milkir_native.function_signature(function, environment_parameters=[
    (0, Ptr64),
  ])
  let target_lower_tick : Ref[@perf.PerfTick?] = { val: None, }
  let observer = if record_metrics {
    Some(target_compile_metrics_observer(target_lower_tick))
  } else {
    None
  }
  let session = try {
    match observer {
      Some(observe) =>
        @x64_target.DirectLoweringSession::new(
          function.name,
          Internal,
          signature.params,
          signature.results,
          context,
          on_event=observe,
        )
      None =>
        @x64_target.DirectLoweringSession::new(
          function.name,
          Internal,
          signature.params,
          signature.results,
          context,
        )
    }
  } catch {
    error => raise X64LoweringFailed(cause=error)
  }
  let native_lower_tick = target_metrics_tick(record_metrics)
  @wasm_native.lower_to_sink(
    function,
    validation_context,
    environment.wasm,
    session.sink(),
    call_abi=wasmoon_call_abi(environment),
    verify_input=compiler_validation(),
    on_event=if record_metrics && @perf.detail_enabled() {
      native_lower_metrics_observer()
    } else {
      fn(_) { () }
    },
  ) catch {
    error => raise NativeLoweringFailed(cause=error)
  }
  record_target_stage(NativeLowering, native_lower_tick) |> ignore
  target_lower_tick.val = target_metrics_tick(record_metrics)
  let selected = session.finish_selected(verify_selected=compiler_validation()) catch {
    error => raise X64LoweringFailed(cause=error)
  }
  let compiled = try {
    match observer {
      Some(observe) =>
        compilation_session.compile_selected(
          selected,
          on_event=observe,
          verify_allocation=compiler_validation(),
        )
      None =>
        compilation_session.compile_selected(
          selected,
          verify_allocation=compiler_validation(),
        )
    }
  } catch {
    error => raise X64CompilationFailed(cause=error)
  }
  let (object, frame_size) = compiled
  { object, frame_size, }
}

///|
fn compile_wasm_body_aarch64_target(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  use_subtype_indirect_check : Bool,
  canonical_type_indices : Array[Int],
  record_metrics? : Bool = false,
  compilation_session? : @aarch64_target.CompilationSession = @aarch64_target.CompilationSession::new(),
) -> AArch64TargetCompilation raise JitPipelineError {
  let environment_tick = detail_metrics_tick(record_metrics)
  let environment = wasmoon_native_environment(
    use_subtype_indirect_check, canonical_type_indices,
  )
  let context = wasm_aarch64_context(environment)
  record_compile_subphase("native_environment", environment_tick)
  let signature = @milkir_native.function_signature(function, environment_parameters=[
    (0, Ptr64),
  ])
  let target_lower_tick : Ref[@perf.PerfTick?] = { val: None, }
  let observer = if record_metrics {
    Some(target_compile_metrics_observer(target_lower_tick))
  } else {
    None
  }
  let session = try {
    match observer {
      Some(observe) =>
        @aarch64_target.DirectLoweringSession::new(
          function.name,
          Internal,
          signature.params,
          signature.results,
          context,
          on_event=observe,
        )
      None =>
        @aarch64_target.DirectLoweringSession::new(
          function.name,
          Internal,
          signature.params,
          signature.results,
          context,
        )
    }
  } catch {
    error => raise AArch64LoweringFailed(cause=error)
  }
  let native_lower_tick = target_metrics_tick(record_metrics)
  @wasm_native.lower_to_sink(
    function,
    validation_context,
    environment.wasm,
    session.sink(),
    call_abi=wasmoon_call_abi(environment),
    verify_input=compiler_validation(),
    on_event=if record_metrics && @perf.detail_enabled() {
      native_lower_metrics_observer()
    } else {
      fn(_) { () }
    },
  ) catch {
    error => raise NativeLoweringFailed(cause=error)
  }
  record_target_stage(NativeLowering, native_lower_tick) |> ignore
  target_lower_tick.val = target_metrics_tick(record_metrics)
  let selected = session.finish_selected(verify_selected=compiler_validation()) catch {
    error => raise AArch64LoweringFailed(cause=error)
  }
  let compiled = try {
    match observer {
      Some(observe) =>
        compilation_session.compile_selected(
          selected,
          on_event=observe,
          verify_allocation=compiler_validation(),
        )
      None =>
        compilation_session.compile_selected(
          selected,
          verify_allocation=compiler_validation(),
        )
    }
  } catch {
    error => raise AArch64CompilationFailed(cause=error)
  }
  let (object, frame_size) = compiled
  { object, frame_size, }
}

///|
pub fn compile_wasm_body_diagnostics_for_target(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  target : NativeTarget,
  use_subtype_indirect_check? : Bool = true,
  canonical_type_indices? : Array[Int] = [],
) -> JitPipelineDiagnostics raise JitPipelineError {
  let environment = wasmoon_native_environment(
    use_subtype_indirect_check, canonical_type_indices,
  )
  let signature = @milkir_native.function_signature(function, environment_parameters=[
    (0, Ptr64),
  ])
  if target is X64 {
    let context = wasm_x64_context(environment)
    let session = @x64_target.DirectLoweringSession::new(
      function.name,
      Internal,
      signature.params,
      signature.results,
      context,
    ) catch {
      error => raise X64LoweringFailed(cause=error)
    }
    @wasm_native.lower_to_sink(
      function,
      validation_context,
      environment.wasm,
      session.sink(),
      call_abi=wasmoon_call_abi(environment),
    ) catch {
      error => raise NativeLoweringFailed(cause=error)
    }
    let selected = session.finish_selected() catch {
      error => raise X64LoweringFailed(cause=error)
    }
    let diagnostics = @x64_target.diagnose_selected(selected) catch {
      error => raise X64CompilationFailed(cause=error)
    }
    return {
      target_vcode: diagnostics.target_vcode,
      allocated_vcode: diagnostics.allocated_vcode,
      code_object: code_object_diagnostic_text(diagnostics.object),
      machine_code: diagnostics.object
      .code()
      .map(byte => @types.to_hex_byte(byte.to_int()))
      .join(" "),
    }
  }
  let context = wasm_aarch64_context(environment)
  let session = @aarch64_target.DirectLoweringSession::new(
    function.name,
    Internal,
    signature.params,
    signature.results,
    context,
  ) catch {
    error => raise AArch64LoweringFailed(cause=error)
  }
  @wasm_native.lower_to_sink(
    function,
    validation_context,
    environment.wasm,
    session.sink(),
    call_abi=wasmoon_call_abi(environment),
  ) catch {
    error => raise NativeLoweringFailed(cause=error)
  }
  let selected = session.finish_selected() catch {
    error => raise AArch64LoweringFailed(cause=error)
  }
  let diagnostics = @aarch64_target.diagnose_selected(selected) catch {
    error => raise AArch64CompilationFailed(cause=error)
  }
  {
    target_vcode: diagnostics.target_vcode,
    allocated_vcode: diagnostics.allocated_vcode,
    code_object: code_object_diagnostic_text(diagnostics.object),
    machine_code: diagnostics.object
    .code()
    .map(byte => @types.to_hex_byte(byte.to_int()))
    .join(" "),
  }
}

///|
pub fn plan_wasm_body_aarch64_code_object(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  use_subtype_indirect_check? : Bool = true,
  canonical_type_indices? : Array[Int] = [],
) -> @code_object.UnlinkedCodeObject raise JitPipelineError {
  compile_wasm_body_aarch64_target(
    function, validation_context, use_subtype_indirect_check, canonical_type_indices,
  ).object
}

///|
pub fn plan_wasm_body_x64_code_object(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  use_subtype_indirect_check? : Bool = true,
  canonical_type_indices? : Array[Int] = [],
) -> @code_object.UnlinkedCodeObject raise JitPipelineError {
  compile_wasm_body_x64_target(
    function, validation_context, use_subtype_indirect_check, canonical_type_indices,
  ).object
}
