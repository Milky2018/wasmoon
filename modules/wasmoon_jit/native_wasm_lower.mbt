///|
extern "C" fn poll_layout_field(index : Int32) -> Int32 = "wasmoon_jit_poll_layout_field"

///|
extern "C" fn gc_offset_references_enabled() -> Int32 = "wasmoon_gc_offset_references_enabled"

///|
let offset_reference_codegen_enabled : Bool = gc_offset_references_enabled() !=
  0

///|
/// Immutable native offsets are shared by compiler environments. Per-function
/// expansion state remains private to each lowering invocation.
let native_struct_view_layout : @wasm_native.StructViewLayout = {
  type_ids_offset: native_layout_field(25),
  type_count_offset: native_layout_field(26),
  allocation_control: native_layout_field(43),
  control_enabled: native_layout_field(44),
  struct_views: native_layout_field(56),
  view_reference: native_layout_field(57),
  view_identity: native_layout_field(58),
  view_fields: native_layout_field(59),
  view_shape: native_layout_field(60),
  view_payload: native_layout_field(61),
  view_bits: native_layout_field(62),
  registry_offset: native_layout_field(68),
  registry_parents: native_layout_field(69),
  registry_type_count: native_layout_field(70),
}

///|
priv struct WasmoonNativeEnvironment {
  wasm : @wasm_native.Environment
  field_paths : Map[String, Array[Int32]]
  runtime_symbols : @wasm_milkir.RuntimeSymbols
}

///|
fn wasmoon_native_environment(
  layout : VMContextLayout,
) -> WasmoonNativeEnvironment {
  let field_paths : Map[String, Array[Int32]] = Map([])
  let runtime_symbols = wasm_runtime_symbols()
  let function_table_field = @native.EnvironmentField::new(
    "wasmoon.vmctx.function_table",
    Ptr64,
  )
  field_paths.set(function_table_field.name, [layout.func_table_offset])

  let gc_heap_field = @native.EnvironmentField::new(
    "wasmoon.vmctx.gc_heap",
    Ptr64,
  )
  field_paths.set(gc_heap_field.name, [layout.gc_heap_offset])
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
    fn(index) {
      let field = @native.EnvironmentField::new(
        "wasmoon.vmctx.table.\{index}.size",
        I64,
      )
      let path = if index == 0 {
        [layout.table0_elements_offset]
      } else {
        [layout.table_sizes_offset, index * layout.pointer_stride]
      }
      field_paths.set(field.name, path)
      field
    },
    fn(helper) {
      @native.ExternalSymbol::new(runtime_symbols.symbol_name(helper))
    },
    // The C helpers publish only after the process verification setting has
    // resolved to ordinary mode. Allocation fault injection changes only
    // allocation attempts; it cannot change the verification setting.
    ordinary_view_publication=true,
    heap_cast_pages=Some(native_layout_field(33)),
    offset_refs=if offset_reference_codegen_enabled {
      Some({
        directory: native_layout_field(71),
        header_flags: native_layout_field(72),
        header_reserved: native_layout_field(73),
        header_size: native_layout_field(74),
      })
    } else {
      None
    },
    struct_views=Some(native_struct_view_layout),
    array_views=Some({
      allocation_control: native_layout_field(43),
      control_enabled: native_layout_field(44),
      array_views: native_layout_field(63),
      view_reference: native_layout_field(64),
      view_payload: native_layout_field(65),
      view_bits: native_layout_field(66),
      view_stride: native_layout_field(67),
    }),
    inline_heap=Some({
      type_ids_offset: native_layout_field(25),
      type_count_offset: native_layout_field(26),
      bump_offset: layout.gc_heap_ptr_offset,
      data: native_layout_field(27),
      size: native_layout_field(28),
      capacity: native_layout_field(29),
      collection_limit: native_layout_field(30),
      layouts: native_layout_field(31),
      layout_capacity: native_layout_field(32),
      object_count: native_layout_field(35),
      live_objects: native_layout_field(36),
      live_count: native_layout_field(37),
      total_allocations: native_layout_field(39),
      quota_denied: native_layout_field(40),
      byte_reservation: native_layout_field(41),
      object_reservation: native_layout_field(42),
      allocation_control: native_layout_field(43),
      control_enabled: native_layout_field(44),
      control_attempts: native_layout_field(45),
      page_offsets: native_layout_field(46),
      page_types: native_layout_field(47),
      page_live_count: native_layout_field(48),
      layout_kind: native_layout_field(49),
      layout_count: native_layout_field(50),
      layout_size: native_layout_field(51),
      layout_shape: native_layout_field(52),
      identity_page_bits: native_layout_field(53),
      identity_window_limit: native_layout_field(54),
      identity_window_page: native_layout_field(55),
    }),
    prepared_arrays=true,
    gc_array_regions=true,
    exclusive_poll_controls=true,
    poll_budget_offset=Some(poll_layout_field(5)),
    gc_heap_field=if layout.gc_heap_offset >= 0 && layout.gc_heap_offset != 255 {
      Some(gc_heap_field)
    } else {
      None
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
  function_index : Int32,
) -> @native_lowering.CallAbiElaboration {
  let hidden_safepoints : Array[@native_lowering.HiddenSafepointAbi] = []
  for symbol in wasmoon_allocation_symbols(environment) {
    hidden_safepoints.push(
      @native_lowering.HiddenSafepointAbi::new(
        symbol,
        AllocationOperands,
        owner=function_index,
      ),
    )
  }
  @native_lowering.CallAbiElaboration::new(
    function_frame=@native_lowering.FunctionRootFrameAbi::new(
      @native.ExternalSymbol::new(gc_function_frame_enter_symbol()),
      @native.ExternalSymbol::new(gc_function_frame_leave_symbol()),
      preserves_mask=true,
      inline_layout=Some({
        execution_offset: poll_layout_field(0),
        active_offset: poll_layout_field(1),
        head_offset: poll_layout_field(4),
      }),
    ),
    hidden_safepoints~,
    scoped_root_limit=4,
  )
}

///|
fn wasm_x64_context(
  environment : WasmoonNativeEnvironment,
) -> @x64_target.LoweringContext raise JitPipelineError {
  let abi = wasm_internal_abi(X64) catch {
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
  let abi = wasm_internal_abi(AArch64) catch {
    error => raise AArch64AbiInvalid(cause=error)
  }
  @aarch64_target.LoweringContext::new(abi).with_environment_field_resolver(field => {
    environment.field_paths.get(field.name)
  })
}

///|
fn lower_wasm_body_to_sink(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  environment : WasmoonNativeEnvironment,
  sink : @native_lowering.TargetSink,
  function_index : Int32,
  record_metrics : Bool,
) -> Unit raise JitPipelineError {
  let tick = target_metrics_tick(record_metrics)
  @wasm_native.lower_to_sink(
    function,
    validation_context,
    environment.wasm,
    sink,
    call_abi=wasmoon_call_abi(environment, function_index),
    verify_input=compiler_validation(),
    on_event=if record_metrics && @perf.detail_enabled() {
      native_lower_metrics_observer()
    } else {
      fn(_) { () }
    },
  ) catch {
    error => raise NativeLoweringFailed(cause=error)
  }
  record_target_stage(NativeLowering, tick) |> ignore
}

///|
fn compile_wasm_body_x64_target(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  context_layout~ : VMContextLayout = vmcontext_layout(),
  function_index~ : Int32 = -1,
  record_metrics~ : Bool = false,
  on_diagnostics~ : ((String, String) -> Unit)? = None,
  compilation_session~ : @x64_target.CompilationSession = @x64_target.CompilationSession::new(),
) -> X64TargetCompilation raise JitPipelineError {
  let environment_tick = detail_metrics_tick(record_metrics)
  let environment = wasmoon_native_environment(context_layout)
  let context = wasm_x64_context(environment)
  record_compile_subphase("native_environment", environment_tick)
  let signature = @milkir_native.function_signature(function, environment_parameters=[
    (0, Ptr64),
  ])
  let target_lower_tick : Ref[@perf.PerfTick?] = { val: None, }
  let observer = if record_metrics {
    target_compile_metrics_observer(target_lower_tick)
  } else {
    fn(_) { () }
  }
  let session = @x64_target.DirectLoweringSession::new(
    function.name,
    Internal,
    signature.params,
    signature.results,
    context,
    on_event=observer,
  ) catch {
    error => raise X64LoweringFailed(cause=error)
  }
  lower_wasm_body_to_sink(
    function,
    validation_context,
    environment,
    session.sink(),
    function_index,
    record_metrics,
  )
  target_lower_tick.val = target_metrics_tick(record_metrics)
  let selected = session.finish_selected(verify_selected=compiler_validation()) catch {
    error => raise X64LoweringFailed(cause=error)
  }
  let compiled = compilation_session.compile_selected(
    selected,
    on_event=observer,
    verify_allocation=compiler_validation(),
    on_diagnostics~,
  ) catch {
    error => raise X64CompilationFailed(cause=error)
  }
  let (object, frame_size) = compiled
  { object, frame_size, }
}

///|
fn compile_wasm_body_aarch64_target(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  context_layout~ : VMContextLayout = vmcontext_layout(),
  function_index~ : Int32 = -1,
  record_metrics~ : Bool = false,
  on_diagnostics~ : ((String, String) -> Unit)? = None,
  compilation_session~ : @aarch64_target.CompilationSession = @aarch64_target.CompilationSession::new(),
) -> AArch64TargetCompilation raise JitPipelineError {
  let environment_tick = detail_metrics_tick(record_metrics)
  let environment = wasmoon_native_environment(context_layout)
  let context = wasm_aarch64_context(environment)
  record_compile_subphase("native_environment", environment_tick)
  let signature = @milkir_native.function_signature(function, environment_parameters=[
    (0, Ptr64),
  ])
  let target_lower_tick : Ref[@perf.PerfTick?] = { val: None, }
  let observer = if record_metrics {
    target_compile_metrics_observer(target_lower_tick)
  } else {
    fn(_) { () }
  }
  let session = @aarch64_target.DirectLoweringSession::new(
    function.name,
    Internal,
    signature.params,
    signature.results,
    context,
    on_event=observer,
  ) catch {
    error => raise AArch64LoweringFailed(cause=error)
  }
  lower_wasm_body_to_sink(
    function,
    validation_context,
    environment,
    session.sink(),
    function_index,
    record_metrics,
  )
  target_lower_tick.val = target_metrics_tick(record_metrics)
  let selected = session.finish_selected(verify_selected=compiler_validation()) catch {
    error => raise AArch64LoweringFailed(cause=error)
  }
  let compiled = compilation_session.compile_selected(
    selected,
    on_event=observer,
    verify_allocation=compiler_validation(),
    on_diagnostics~,
  ) catch {
    error => raise AArch64CompilationFailed(cause=error)
  }
  let (object, frame_size) = compiled
  { object, frame_size, }
}

///|
/// Inspect Wasm MilkIR through the production compiler. Legacy layout and the
/// unknown owner index remain defaults for existing standalone callers; module
/// diagnostics should use a shaped NativeCompiler and the absolute function index.
pub fn compile_wasm_body_diagnostics_for_target(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  target : NativeTarget,
  context_shape~ : ContextShape = Legacy,
  function_index~ : Int32 = -1,
) -> JitPipelineDiagnostics raise JitPipelineError {
  NativeCompiler::new(target, context_shape~).diagnose_wasm_body(
    function,
    validation_context,
    function_index~,
  )
}

///|
/// Observe the production pipeline with this compiler's target and context layout.
pub fn NativeCompiler::diagnose_wasm_body(
  self : NativeCompiler,
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  function_index~ : Int32,
) -> JitPipelineDiagnostics raise JitPipelineError {
  let renderings : Ref[(String, String)] = { val: ("", ""), }
  let (object, _) = self.compile_wasm_body(
    function,
    validation_context,
    function_index~,
    on_diagnostics=Some(fn(target_vcode, allocated_vcode) {
      renderings.val = (target_vcode, allocated_vcode)
    }),
  )
  {
    target_vcode: renderings.val.0,
    allocated_vcode: renderings.val.1,
    code_object: code_object_diagnostic_text(object),
    machine_code: object
    .code()
    .map(byte => @types.to_hex_byte(byte.to_int()))
    .join(" "),
  }
}

///|
pub fn plan_wasm_body_aarch64_code_object(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
) -> @code_object.UnlinkedCodeObject raise JitPipelineError {
  compile_wasm_body_aarch64_target(function, validation_context).object
}

///|
pub fn plan_wasm_body_x64_code_object(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
) -> @code_object.UnlinkedCodeObject raise JitPipelineError {
  compile_wasm_body_x64_target(function, validation_context).object
}
