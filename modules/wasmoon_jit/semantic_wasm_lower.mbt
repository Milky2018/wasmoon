///|
priv struct WasmoonSemanticEnvironment {
  wasm : @wasm_machv.Environment
  field_paths : Map[String, Array[Int]]
  runtime_symbols : @wasm_milkir.RuntimeSymbols
}

///|
fn wasmoon_semantic_environment(
  use_subtype_indirect_check : Bool,
  canonical_type_indices : Array[Int],
) -> WasmoonSemanticEnvironment {
  let layout = vmcontext_layout()
  let field_paths : Map[String, Array[Int]] = Map([])
  let runtime_symbols = wasm_runtime_symbols()
  let function_table_field = @semantic_machv.EnvironmentField::new(
    "wasmoon.vmctx.function_table",
    Ptr64,
  )
  field_paths.set(function_table_field.name, [layout.func_table_offset])
  let canonical_type_indices = canonical_type_indices.copy()
  let wasm = @wasm_machv.Environment::new(
    fn(index) {
      let name = "wasm.func.\{index}"
      @semantic_machv.CodeSymbol::new(name)
    },
    fn(index) {
      let field = @semantic_machv.EnvironmentField::new(
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
      let field = @semantic_machv.EnvironmentField::new(
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
      @semantic_machv.ExternalSymbol::new(runtime_symbols.symbol_name(helper))
    },
  )
  { wasm, field_paths, runtime_symbols, }
}

///|
fn wasmoon_allocation_symbols(
  environment : WasmoonSemanticEnvironment,
) -> Array[@semantic_machv.ExternalSymbol] {
  [
    @semantic_machv.ExternalSymbol::new(
      environment.runtime_symbols.symbol_name(GcAllocStructSlow),
    ),
    @semantic_machv.ExternalSymbol::new(
      environment.runtime_symbols.symbol_name(GcAllocArrayFromValuesSlow),
    ),
    @semantic_machv.ExternalSymbol::new(
      environment.runtime_symbols.symbol_name(GcAllocArraySlow),
    ),
  ]
}

///|
fn build_wasmoon_aarch64_target(
  semantic : @semantic_machv.SelectionPlan,
  environment : WasmoonSemanticEnvironment,
  record_metrics? : Bool = false,
  compilation_session? : @aarch64_target.CompilationSession = @aarch64_target.CompilationSession::new(),
) -> AArch64TargetCompilation raise JitPipelineError {
  build_aarch64_selection_plan(
    semantic,
    environment_field_path=fn(field : @semantic_machv.EnvironmentField) {
      environment.field_paths.get(field.name)
    },
    allocation_symbols=wasmoon_allocation_symbols(environment),
    record_metrics~,
    compilation_session~,
    root_scope_symbols=(
      @semantic_machv.ExternalSymbol::new(gc_push_root_scope_symbol()),
      @semantic_machv.ExternalSymbol::new(gc_pop_root_scope_symbol()),
    ),
  )
}

///|
fn build_wasmoon_x64_target(
  semantic : @semantic_machv.SelectionPlan,
  environment : WasmoonSemanticEnvironment,
  record_metrics? : Bool = false,
  compilation_session? : @x64_target.CompilationSession = @x64_target.CompilationSession::new(),
) -> X64TargetCompilation raise JitPipelineError {
  build_x64_selection_plan(
    semantic,
    environment_field_path=fn(field : @semantic_machv.EnvironmentField) {
      environment.field_paths.get(field.name)
    },
    allocation_symbols=wasmoon_allocation_symbols(environment),
    record_metrics~,
    compilation_session~,
    root_scope_symbols=(
      @semantic_machv.ExternalSymbol::new(gc_push_root_scope_symbol()),
      @semantic_machv.ExternalSymbol::new(gc_pop_root_scope_symbol()),
    ),
  )
}

///|
fn lower_wasm_body_semantic_with_environment(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  environment : WasmoonSemanticEnvironment,
  on_event? : (@milkir_machv.SemanticLowerEvent) -> Unit = fn(_) { () },
) -> @semantic_machv.Function raise JitPipelineError {
  @wasm_machv.lower_function(
    function,
    validation_context,
    environment.wasm,
    on_event~,
  ) catch {
    error => raise SemanticLoweringFailed(cause=error)
  }
}

///|
fn lower_wasm_body_selection_plan_with_environment(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  environment : WasmoonSemanticEnvironment,
  on_event? : (@milkir_machv.SemanticLowerEvent) -> Unit = fn(_) { () },
) -> @semantic_machv.SelectionPlan raise JitPipelineError {
  @wasm_machv.lower_selection_plan(
    function,
    validation_context,
    environment.wasm,
    on_event~,
  ) catch {
    error => raise SemanticLoweringFailed(cause=error)
  }
}

///|
pub fn lower_wasm_body_semantic_machv(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  use_subtype_indirect_check? : Bool = true,
  canonical_type_indices? : Array[Int] = [],
) -> @semantic_machv.Function raise JitPipelineError {
  let environment = wasmoon_semantic_environment(
    use_subtype_indirect_check, canonical_type_indices,
  )
  lower_wasm_body_semantic_with_environment(
    function, validation_context, environment,
  )
}

///|
/// Render every verified native compilation checkpoint without exposing
/// concrete target construction types to diagnostics consumers.
pub fn compile_wasm_body_diagnostics_for_target(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  target : NativeTarget,
  use_subtype_indirect_check? : Bool = true,
  canonical_type_indices? : Array[Int] = [],
) -> JitPipelineDiagnostics raise JitPipelineError {
  let environment = wasmoon_semantic_environment(
    use_subtype_indirect_check, canonical_type_indices,
  )
  let semantic = lower_wasm_body_semantic_with_environment(
    function, validation_context, environment,
  )
  let semantic_machv = semantic.print()
  if target is AArch64 {
    let diagnostics = diagnose_aarch64_target(
      semantic,
      environment_field_path=fn(field : @semantic_machv.EnvironmentField) {
        environment.field_paths.get(field.name)
      },
      allocation_symbols=wasmoon_allocation_symbols(environment),
      root_scope_symbols=(
        @semantic_machv.ExternalSymbol::new(gc_push_root_scope_symbol()),
        @semantic_machv.ExternalSymbol::new(gc_pop_root_scope_symbol()),
      ),
    )
    return {
      semantic_machv,
      target_vcode: diagnostics.target_vcode,
      allocated_vcode: diagnostics.allocated_vcode,
      code_object: code_object_diagnostic_text(diagnostics.object),
      machine_code: diagnostics.object
      .code()
      .map(byte => @types.to_hex_byte(byte.to_int()))
      .join(" "),
    }
  }
  let diagnostics = diagnose_x64_target(
    semantic,
    environment_field_path=fn(field : @semantic_machv.EnvironmentField) {
      environment.field_paths.get(field.name)
    },
    allocation_symbols=wasmoon_allocation_symbols(environment),
    root_scope_symbols=(
      @semantic_machv.ExternalSymbol::new(gc_push_root_scope_symbol()),
      @semantic_machv.ExternalSymbol::new(gc_pop_root_scope_symbol()),
    ),
  )
  {
    semantic_machv,
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
fn compile_wasm_body_aarch64_target(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  use_subtype_indirect_check : Bool,
  canonical_type_indices : Array[Int],
  record_metrics? : Bool = false,
  compilation_session? : @aarch64_target.CompilationSession = @aarch64_target.CompilationSession::new(),
) -> AArch64TargetCompilation raise JitPipelineError {
  let environment_tick = detail_metrics_tick(record_metrics)
  let environment = wasmoon_semantic_environment(
    use_subtype_indirect_check, canonical_type_indices,
  )
  record_compile_subphase("semantic_environment", environment_tick)
  let semantic_lower_tick = target_metrics_tick(record_metrics)
  let semantic = if record_metrics && @perf.detail_enabled() {
    lower_wasm_body_selection_plan_with_environment(
      function,
      validation_context,
      environment,
      on_event=semantic_lower_metrics_observer(),
    )
  } else {
    lower_wasm_body_selection_plan_with_environment(
      function, validation_context, environment,
    )
  }
  record_target_stage(SemanticLowering, semantic_lower_tick) |> ignore
  build_wasmoon_aarch64_target(
    semantic,
    environment,
    record_metrics~,
    compilation_session~,
  )
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
  let environment = wasmoon_semantic_environment(
    use_subtype_indirect_check, canonical_type_indices,
  )
  record_compile_subphase("semantic_environment", environment_tick)
  let semantic_lower_tick = target_metrics_tick(record_metrics)
  let semantic = if record_metrics && @perf.detail_enabled() {
    lower_wasm_body_selection_plan_with_environment(
      function,
      validation_context,
      environment,
      on_event=semantic_lower_metrics_observer(),
    )
  } else {
    lower_wasm_body_selection_plan_with_environment(
      function, validation_context, environment,
    )
  }
  record_target_stage(SemanticLowering, semantic_lower_tick) |> ignore
  build_wasmoon_x64_target(
    semantic,
    environment,
    record_metrics~,
    compilation_session~,
  )
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
