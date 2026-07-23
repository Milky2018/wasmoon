///|
priv struct WasmoonSemanticEnvironment {
  wasm : @wasm_machv.Environment
  field_paths : Map[String, Array[Int]]
  runtime_symbols : @wasm_milkir.RuntimeSymbols
}

///|
fn semantic_runtime_symbol(
  symbols : @wasm_milkir.RuntimeSymbols,
  capability : String,
) -> String {
  match capability {
    "memory.grow" => symbols.memory_grow
    "memory.size" => symbols.memory_size
    "memory.fill" => symbols.memory_fill
    "memory.copy" => symbols.memory_copy
    "memory.init" => symbols.memory_init
    "data.drop" => symbols.data_drop
    "table.grow" => symbols.table_grow
    "table.fill" => symbols.table_fill
    "table.copy" => symbols.table_copy
    "table.init" => symbols.table_init
    "elem.drop" => symbols.elem_drop
    "gc.ref_test" => symbols.gc_ref_test
    "gc.ref_cast" => symbols.gc_ref_cast
    "gc.struct_get" => symbols.gc_struct_get
    "gc.struct_set" => symbols.gc_struct_set
    "gc.array_get" => symbols.gc_array_get
    "gc.array_set" => symbols.gc_array_set
    "gc.array_len" => symbols.gc_array_len
    "gc.array_fill" => symbols.gc_array_fill
    "gc.array_copy" => symbols.gc_array_copy
    "gc.array_new_data" => symbols.gc_array_new_data
    "gc.array_new_elem" => symbols.gc_array_new_elem
    "gc.array_init_data" => symbols.gc_array_init_data
    "gc.array_init_elem" => symbols.gc_array_init_elem
    "gc.type_check_subtype" => symbols.gc_type_check_subtype
    "gc.register_struct_inline" => symbols.gc_register_struct_inline
    "gc.register_array_inline" => symbols.gc_register_array_inline
    "gc.alloc_struct_slow" => symbols.gc_alloc_struct_slow
    "gc.alloc_array_from_values_slow" => symbols.gc_alloc_array_from_values_slow
    "gc.alloc_array_slow" => symbols.gc_alloc_array_slow
    "exception.try_begin" => symbols.exception_try_begin
    "exception.try_end" => symbols.exception_try_end
    "exception.throw" => symbols.exception_throw
    "exception.throw_tag" => symbols.exception_throw_tag
    "exception.throw_ref" => symbols.exception_throw_ref
    "exception.delegate" => symbols.exception_delegate
    "exception.get_tag" => symbols.exception_get_tag
    "exception.get_value" => symbols.exception_get_value
    "exception.get_value_count" => symbols.exception_get_value_count
    "exception.sigsetjmp" => symbols.exception_sigsetjmp
    "exception.spill_locals" => symbols.exception_spill_locals
    "exception.get_spilled_local" => symbols.exception_get_spilled_local
    _ => abort("missing Wasmoon runtime capability '\{capability}'")
  }
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
    fn(capability) {
      @semantic_machv.ExternalSymbol::new(
        semantic_runtime_symbol(runtime_symbols, capability),
      )
    },
  )
  { wasm, field_paths, runtime_symbols }
}

///|
fn wasmoon_allocation_symbols(
  environment : WasmoonSemanticEnvironment,
) -> Array[@semantic_machv.ExternalSymbol] {
  [
    @semantic_machv.ExternalSymbol::new(
      environment.runtime_symbols.gc_alloc_struct_slow,
    ),
    @semantic_machv.ExternalSymbol::new(
      environment.runtime_symbols.gc_alloc_array_from_values_slow,
    ),
    @semantic_machv.ExternalSymbol::new(
      environment.runtime_symbols.gc_alloc_array_slow,
    ),
  ]
}

///|
fn build_wasmoon_aarch64_target(
  semantic : @semantic_machv.Function,
  environment : WasmoonSemanticEnvironment,
  record_metrics? : Bool = false,
) -> AArch64TargetCompilation raise JitPipelineError {
  build_aarch64_target(
    semantic,
    environment_field_path=fn(field : @semantic_machv.EnvironmentField) {
      environment.field_paths.get(field.name)
    },
    allocation_symbols=wasmoon_allocation_symbols(environment),
    record_metrics~,
    root_scope_symbols=(
      @semantic_machv.ExternalSymbol::new(gc_push_root_scope_symbol()),
      @semantic_machv.ExternalSymbol::new(gc_pop_root_scope_symbol()),
    ),
  )
}

///|
fn build_wasmoon_x64_target(
  semantic : @semantic_machv.Function,
  environment : WasmoonSemanticEnvironment,
  record_metrics? : Bool = false,
) -> X64TargetCompilation raise JitPipelineError {
  build_x64_target(
    semantic,
    environment_field_path=fn(field : @semantic_machv.EnvironmentField) {
      environment.field_paths.get(field.name)
    },
    allocation_symbols=wasmoon_allocation_symbols(environment),
    record_metrics~,
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
) -> @semantic_machv.Function raise JitPipelineError {
  @wasm_machv.lower_function(function, validation_context, environment.wasm) catch {
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
) -> AArch64TargetCompilation raise JitPipelineError {
  let environment = wasmoon_semantic_environment(
    use_subtype_indirect_check, canonical_type_indices,
  )
  let semantic_lower_tick = target_metrics_tick(record_metrics)
  let semantic = lower_wasm_body_semantic_with_environment(
    function, validation_context, environment,
  )
  record_target_stage("lower", semantic_lower_tick)
  build_wasmoon_aarch64_target(semantic, environment, record_metrics~)
}

///|
fn compile_wasm_body_x64_target(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  use_subtype_indirect_check : Bool,
  canonical_type_indices : Array[Int],
  record_metrics? : Bool = false,
) -> X64TargetCompilation raise JitPipelineError {
  let environment = wasmoon_semantic_environment(
    use_subtype_indirect_check, canonical_type_indices,
  )
  let semantic_lower_tick = target_metrics_tick(record_metrics)
  let semantic = lower_wasm_body_semantic_with_environment(
    function, validation_context, environment,
  )
  record_target_stage("lower", semantic_lower_tick)
  build_wasmoon_x64_target(semantic, environment, record_metrics~)
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
