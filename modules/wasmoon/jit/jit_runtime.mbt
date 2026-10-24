///|
/// JIT Execution Runtime
/// Loads and executes verified v9 JIT artifacts.

///|
/// JIT-compiled function ready for execution
pub struct JITFunction {
  func_idx : Int32
  name : String
  priv func_ptr : Int64
  priv code_size : Int32
  priv source_ranges : Array[(Int32, Int32, Int64)]
  param_types : ReadOnlyArray[@types.ValueType] // Parameter types for proper register allocation
  result_types : ReadOnlyArray[@types.ValueType] // Return types (empty = void, 1 = single, 2+ = multi-value)
}

///|
/// Error when loading a precompiled JIT module
pub suberror JITModuleLoadError {
  ContextAllocationFailed(total_funcs~ : Int32)
  UnsupportedImport(
    import_idx~ : Int32,
    module_name~ : String,
    func_name~ : String
  )
  ImportTrampolineAllocationFailed(
    import_idx~ : Int32,
    module_name~ : String,
    func_name~ : String,
    code_size~ : Int32
  )
  ImportTrampolineCompilationFailed(
    import_idx~ : Int32,
    module_name~ : String,
    func_name~ : String,
    message~ : String
  )
  ArtifactInstallationFailed(cause~ : @wasmoon_jit.JitInstallError)
  CodeQuotaExceeded
  FunctionMetadataRegistrationFailed(func_idx~ : Int32, message~ : String)
} derive(Debug)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for JITModuleLoadError with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
fn JITFunction::JITFunction(
  func_idx : Int32,
  name : String,
  func_ptr : Int64,
  code_size : Int32,
  param_types : ReadOnlyArray[@types.ValueType],
  result_types : ReadOnlyArray[@types.ValueType],
  source_ranges : Array[(Int32, Int32, Int64)],
) -> JITFunction {
  {
    func_idx,
    name,
    func_ptr,
    code_size,
    param_types,
    result_types,
    source_ranges,
  }
}

///|
fn JITFunction::wasm_offset(
  self : JITFunction,
  native_offset : Int32,
) -> Int64? {
  let mut lo = 0
  let mut hi = self.source_ranges.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if self.source_ranges[mid].0 <= native_offset {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo == 0 {
    return None
  }
  let (_, end, offset) = self.source_ranges[lo - 1]
  if native_offset < end {
    Some(offset)
  } else {
    None
  }
}

///|
/// Address range for PC-to-function mapping (sorted by start address)
struct AddressRange {
  start : Int64 // Function start address
  end : Int64 // Function end address (start + code_size)
  func_idx : Int32 // Wasm function index
} derive(Debug)

///|
/// Loaded precompiled module with executable functions
struct JITModule {
  functions : Map[Int32, JITFunction]
  callables : Map[Int32, @wasmoon_jit.NativeCallable]
  mut callable_owners : Int32
  mut close_requested : Bool
  by_name : Map[String, Int32]
  address_ranges : Array[AddressRange] // Sorted by start address for binary search
  mut context : JITContext?
  mut debug_db : @wasmoon_jit.JITDebugDB?
  mut last_trap_report : @wasmoon_jit.TrapReport?
  // Keep generated process-local import trampolines alive.
  owned_trampolines : Array[@wasmoon_jit.InstalledTrampoline]
  // Keep the transactionally installed artifact alive.
  mut installed_code : @wasmoon_jit.InstalledCode?
  mut store_functions : Array[Int32]
  mut cancellation_safepoints : Bool
}

///|
pub fn JITModule::JITModule() -> JITModule {
  {
    functions: Map([]),
    callables: Map([]),
    callable_owners: 0,
    close_requested: false,
    by_name: Map([]),
    address_ranges: [],
    context: None,
    debug_db: None,
    last_trap_report: None,
    owned_trampolines: [],
    installed_code: None,
    store_functions: [],
    cancellation_safepoints: false,
  }
}

///|
fn artifact_target_architecture(
  artifact : @artifact.Artifact,
) -> @wasmoon_jit.NativeTarget {
  match artifact.manifest.target.architecture {
    X64 => X64
    AArch64 => AArch64
  }
}

///|
fn artifact_context_function_count(
  artifact : @artifact.Artifact,
  signature_count : Int32,
) -> Int32 {
  let mut count = signature_count
  for import_ in artifact.imports {
    if import_.function_index >= count {
      count = import_.function_index + 1
    }
  }
  for function in artifact.functions {
    if function.identity.function_index >= count {
      count = function.identity.function_index + 1
    }
  }
  count
}

///|
fn artifact_function_name(
  function_index : Int32,
  function_names : Array[String],
) -> String {
  if function_index >= 0 &&
    function_index < function_names.length() &&
    !function_names[function_index].is_empty() {
    function_names[function_index]
  } else {
    "func_\{function_index}"
  }
}

///|
fn stage_artifact_imports(
  artifact : @artifact.Artifact,
  func_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])],
  external_imports : Map[String, Map[String, Int64]],
  owned_trampolines : Array[@wasmoon_jit.InstalledTrampoline],
  resource_budget : @runtime.ResourceBudget?,
) -> Map[String, Int64] raise JITModuleLoadError {
  let import_targets : Map[String, Int64] = Map([])
  let target = artifact_target_architecture(artifact)
  let trampoline_installer = @wasmoon_jit.JitCodeInstaller::new(
    fn(_) { None },
    code_quota=resource_budget.map(budget => budget.native_quota(CodeBytes)),
  )
  for import_ in artifact.imports {
    let function_index = import_.function_index
    let resolved = @wasmoon_jit.resolve_import_function_ptr(
      external_imports,
      import_.module_name,
      import_.function_name,
    )
    guard resolved is Some(raw_pointer) else {
      raise UnsupportedImport(
        import_idx=function_index,
        module_name=import_.module_name,
        func_name=import_.function_name,
      )
    }
    let pointer = if raw_pointer < 0L {
      let host_func_addr = (-(raw_pointer + 1L)).to_int()
      let (param_types, result_types) = if function_index >= 0 &&
        function_index < func_signatures.length() {
        func_signatures[function_index]
      } else {
        ([], [])
      }
      let trampoline = @wasmoon_jit.build_hostcall_import_trampoline_for_target(
        param_types, result_types, host_func_addr, target,
      ) catch {
        error =>
          raise ImportTrampolineCompilationFailed(
            import_idx=function_index,
            module_name=import_.module_name,
            func_name=import_.function_name,
            message=error.to_string(),
          )
      }
      let code = trampoline_installer.install_trampoline(trampoline.code) catch {
        CodeQuotaExceeded => raise CodeQuotaExceeded
        _ =>
          raise ImportTrampolineAllocationFailed(
            import_idx=function_index,
            module_name=import_.module_name,
            func_name=import_.function_name,
            code_size=trampoline.code.length(),
          )
      }
      let pointer = code.entry_address()
      owned_trampolines.push(code)
      pointer
    } else {
      raw_pointer
    }
    import_targets.set(import_.symbol.name, pointer)
  }
  import_targets
}

///|
/// Load a verified v9 artifact without exposing any partially initialized
/// context, function table, executable mapping, or metadata registration.
pub fn JITModule::load_artifact(
  loaded : @wasmoon_jit.LoadedArtifact,
  func_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])],
  function_names~ : Array[String] = [],
  debug_db~ : @wasmoon_jit.JITDebugDB? = None,
  resource_budget~ : @runtime.ResourceBudget? = None,
) -> JITModule raise JITModuleLoadError {
  JITModule::load_artifact_with_imports(
    loaded,
    func_signatures,
    Map([]),
    function_names~,
    debug_db~,
    resource_budget~,
  )
}

///|
/// Load a verified v9 artifact with embedding-provided import addresses.
pub fn JITModule::load_artifact_with_imports(
  loaded : @wasmoon_jit.LoadedArtifact,
  func_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])],
  external_imports : Map[String, Map[String, Int64]],
  function_names~ : Array[String] = [],
  debug_db~ : @wasmoon_jit.JITDebugDB? = None,
  resource_budget~ : @runtime.ResourceBudget? = None,
) -> JITModule raise JITModuleLoadError {
  load_artifact_with_imports_using_registrar(
    loaded,
    func_signatures,
    external_imports,
    function_names,
    debug_db,
    fn(context) { loaded.bind_safepoints(context.ctx) },
    resource_budget~,
  )
}

///|
fn load_artifact_with_imports_using_registrar(
  loaded : @wasmoon_jit.LoadedArtifact,
  func_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])],
  external_imports : Map[String, Map[String, Int64]],
  function_names : Array[String],
  debug_db : @wasmoon_jit.JITDebugDB?,
  register_safepoints : (JITContext) -> Bool,
  resource_budget~ : @runtime.ResourceBudget? = None,
) -> JITModule raise JITModuleLoadError {
  let artifact = loaded.artifact()
  let total_funcs = artifact_context_function_count(
    artifact,
    func_signatures.length(),
  )
  guard JITContext::try_alloc(total_funcs, loaded, resource_budget~)
    is Some(ctx) else {
    raise ContextAllocationFailed(total_funcs~)
  }
  errdefer ctx.close()
  if !register_safepoints(ctx) {
    raise FunctionMetadataRegistrationFailed(
      func_idx=0,
      message="failed to register GC safepoints",
    )
  }
  let jit_module = JITModule::JITModule()
  errdefer jit_module.close()
  let import_targets = stage_artifact_imports(
    artifact,
    func_signatures,
    external_imports,
    jit_module.owned_trampolines,
    resource_budget,
  )
  let runtime_symbols = @wasmoon_jit.RuntimeSymbolResolver::with_wasmoon_runtime_symbols()
  let installer = @wasmoon_jit.JitCodeInstaller::new(
    fn(target) {
      match target {
        External(symbol) =>
          match import_targets.get(symbol.name) {
            Some(pointer) => Some(pointer)
            None => runtime_symbols.resolve(symbol.name)
          }
        Code(_) | Data(_) => None
      }
    },
    code_quota=resource_budget.map(budget => budget.native_quota(CodeBytes)),
  )
  let installed = installer.install(loaded.verified()) catch {
    error => raise ArtifactInstallationFailed(cause=error)
  }
  errdefer installed.release()
  for import_ in installed.imports() {
    ctx.set_func(import_.identity().function_index, import_.address())
  }
  for function in installed.functions() {
    let identity = function.identity()
    let function_index = identity.function_index
    ctx.set_func(function_index, function.entry_address())
    let (param_types, result_types) = if function_index >= 0 &&
      function_index < func_signatures.length() {
      func_signatures[function_index]
    } else {
      ([], [])
    }
    let name = artifact_function_name(function_index, function_names)
    jit_module.functions.set(
      function_index,
      JITFunction(
        function_index,
        name,
        function.entry_address(),
        function.code_size(),
        ReadOnlyArray::from_array(param_types),
        ReadOnlyArray::from_array(result_types),
        function
        .sources()
        .filter_map(site => {
          if site.length > 0 && site.source.byte_offset is Some(offset) {
            Some((site.offset, site.offset + site.length, offset))
          } else {
            None
          }
        }),
      ),
    )
    jit_module.by_name.set(name, function_index)
    jit_module.address_ranges.push({
      start: function.code_address(),
      end: function.code_address() + function.code_size().to_int64(),
      func_idx: function_index,
    })
  }
  jit_module.address_ranges.sort_by(fn(a, b) { a.start.compare(b.start) })
  for index in 0..<ctx.ctx.func_count() {
    let target = ctx.ctx.func_ptr(index)
    if target == 0L {
      continue
    }
    let callable = ctx.ctx.bind_callable(target) catch {
      cause => raise ArtifactInstallationFailed(cause~)
    }
    jit_module.callables.set(index, callable)
    ctx.ctx.set_func(index, callable.entry_address())
  }
  jit_module.context = Some(ctx)
  jit_module.debug_db = debug_db
  jit_module.installed_code = Some(installed)
  jit_module.cancellation_safepoints = artifact.manifest.policy.cancellation_safepoints
  jit_module
}

///|
/// Close this module and release all process-local executable mappings.
///
/// The module is terminal after this call. The caller must first finish or
/// cancel every invocation and continuation that can enter its code.
pub fn JITModule::close(self : JITModule) -> Unit {
  self.close_requested = true
  if self.callable_owners == 0 {
    self.release_code()
  }
}

///|
/// Retain executable state until the Store containing its references closes.
/// Releasing the capability twice is harmless.
pub fn JITModule::retain_callable_owner(self : JITModule) -> () -> Unit {
  self.callable_owners += 1
  let active = Ref(true)
  fn() {
    if active.val {
      active.val = false
      self.callable_owners -= 1
      if self.callable_owners == 0 && self.close_requested {
        self.release_code()
      }
    }
  }
}

///|
fn JITModule::release_code(self : JITModule) -> Unit {
  if self.context is Some(context) {
    context.close()
  }
  self.context = None
  for _, callable in self.callables {
    callable.release()
  }
  self.callables.clear()
  for trampoline in self.owned_trampolines {
    trampoline.release()
  }
  self.owned_trampolines.clear()
  if self.installed_code is Some(installed) {
    installed.release()
  }
  self.installed_code = None
  self.functions.clear()
  self.by_name.clear()
  self.address_ranges.clear()
}

///|
/// Get the number of functions in the function table
/// Returns 0 if no context is available
pub fn JITModule::get_func_count(self : JITModule) -> Int32 {
  match self.context {
    Some(context) => context.ctx.func_count()
    None => 0
  }
}

///|
/// Refresh one Store-owned table from the context that borrowed it.
pub fn JITModule::refresh_table_layout(
  self : JITModule,
  table_idx : Int32,
) -> Bool {
  match self.context {
    Some(context) => context.refresh_table_layout(table_idx)
    None => false
  }
}

///|
/// Get a function by index
pub fn JITModule::get_func(self : JITModule, func_idx : Int32) -> JITFunction? {
  self.functions.get(func_idx)
}

///|
/// Get a function by name
pub fn JITModule::get_func_by_name(
  self : JITModule,
  name : String,
) -> JITFunction? {
  match self.by_name.get(name) {
    Some(idx) => self.functions.get(idx)
    None => None
  }
}

///|
/// Get function pointer by function index (for indirect table initialization)
/// Returns the executable code pointer for the function, or 0 if not found
pub fn JITModule::get_func_ptr(self : JITModule, func_idx : Int32) -> Int64 {
  if self.callables.get(func_idx) is Some(callable) {
    return callable.entry_address()
  }
  // Keep transaction-owned mappings reachable while returning their address.
  self.installed_code |> ignore
  match self.functions.get(func_idx) {
    Some(f) => f.func_ptr
    None =>
      match self.context {
        Some(context) => context.ctx.func_ptr(func_idx)
        None => 0L
      }
  }
}

///|
/// Find the compiled wasm function that contains `pc` (best-effort), returning:
/// (func_idx, function, native_offset_in_function_bytes). The displacement is
/// never an original input-module byte offset.
/// Uses binary search on sorted address_ranges for O(log n) lookup.
pub fn JITModule::find_func_by_pc(
  self : JITModule,
  pc : Int64,
) -> (Int32, JITFunction, Int32)? {
  if pc == 0L || self.address_ranges.is_empty() {
    return None
  }
  // Binary search: find the last range where start <= pc
  let mut lo = 0
  let mut hi = self.address_ranges.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if self.address_ranges[mid].start <= pc {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  // lo-1 is the last index where start <= pc
  if lo == 0 {
    return None
  }
  let range = self.address_ranges[lo - 1]
  if pc < range.end {
    let offset = (pc - range.start).to_int()
    match self.functions.get(range.func_idx) {
      Some(f) => Some((range.func_idx, f, offset))
      None => None
    }
  } else {
    None // PC is not within any known function range
  }
}

///|
/// Get function pointer by name
/// Returns the executable code pointer for the function, or 0 if not found
pub fn JITModule::get_func_ptr_by_name(
  self : JITModule,
  name : String,
) -> Int64 {
  match self.get_func_by_name(name) {
    Some(f) => f.func_ptr
    None => 0L
  }
}

///|
/// Export all function pointers as a map from name to function pointer
/// Used for cross-module imports
pub fn JITModule::export_functions(self : JITModule) -> Map[String, Int64] {
  let exports : Map[String, Int64] = Map([])
  for name, _idx in self.by_name {
    let ptr = self.get_func_ptr_by_name(name)
    if ptr != 0L {
      exports.set(name, ptr)
    }
  }
  exports
}

///|
/// Returns the last structured trap report from `call_with_context`.
/// Returns `None` if no trap has been observed on this module.
pub fn JITModule::get_last_trap_report(
  self : JITModule,
) -> @wasmoon_jit.TrapReport? {
  self.last_trap_report
}

///|
/// Call a function using the JIT context (for functions that need to call other functions)
/// Returns Array[Int64] where each element corresponds to a return value:
/// - For I32/I64: the value is directly in Int64
/// - For F32/F64: the value is the bits of a f64 (Double) reinterpreted as Int64
///   (JIT internally promotes f32 to f64)
pub fn JITModule::call_with_context(
  self : JITModule,
  func : JITFunction,
  args : Array[Int64],
) -> Array[Int64] raise JITTrap {
  match self.context {
    Some(ctx) => {
      self.last_trap_report = None
      // Calculate number of result slots (V128 needs 2 slots, others need 1)
      let mut num_result_slots = 0
      for result_type in func.result_types {
        if result_type is V128 {
          num_result_slots = num_result_slots + 2
        } else {
          num_result_slots = num_result_slots + 1
        }
      }
      let results : Array[Int64] = Array::make(num_result_slots, 0L)
      let mut call_error : JITTrap? = None
      let frame_roots = @wasmoon_jit.collect_gc_root_args(
        args,
        func.param_types,
      )
      self.begin_call_gc(func.func_idx, frame_roots)
      ctx.call_multi_return(
        func.func_ptr,
        args,
        func.param_types,
        results,
        func.result_types,
      ) catch {
        e => call_error = Some(e)
      }
      self.gc_end_frame()
      self.gc_use_func_safepoints(-1)
      self.gc_set_root_scratch([]) |> ignore
      match call_error {
        Some(JITTrap(msg)) => {
          let report = self.build_trap_report(msg)
          self.last_trap_report = Some(report)
          raise JITTrap(@wasmoon_jit.format_trap_report_message(report))
        }
        Some(JITNativeFiberFailure(message)) =>
          raise JITNativeFiberFailure(message)
        Some(JITExit(code)) => raise JITExit(code)
        Some(JITResourceLimit(kind)) => raise JITResourceLimit(kind)
        Some(JITCancelled) => raise JITCancelled
        None => ()
      }
      results
    }
    None => [] // No context, cannot call
  }
}

///|
/// Result of advancing a stackful native JIT call.
pub(all) enum JITContinuationOutcome {
  JITReturned(Array[Int64])
  JITSuspended(@wasmoon_jit.NativeSuspensionReason, JITCallContinuation)
}

///|
/// One stackful native JIT call parked at an imported hostcall.
///
/// The continuation retains its installed code, argument/result buffer, trap
/// activation, and GC metadata until it returns or is cancelled.
struct JITCallContinuation {
  jit_module : JITModule
  func : JITFunction
  call : JITContextContinuation
  entry_roots : Array[Int64]
  first_entry : Array[Bool]
  gc_frame_active : Array[Bool]
  active : Array[Bool]
}

///|
priv enum JITContinuationFrameDisposition {
  // The native activation restored the frame to the JIT context.
  AttachedFrame
  // Cancelling a parked activation released its detached frame chain.
  DetachedFrameReleased
}

///|
fn JITCallContinuation::finish(
  self : JITCallContinuation,
  frame_disposition : JITContinuationFrameDisposition,
) -> Unit {
  self.active[0] = false
  if self.gc_frame_active[0] {
    self.gc_frame_active[0] = false
    if frame_disposition is AttachedFrame {
      self.jit_module.gc_end_frame()
    }
  }
  self.jit_module.gc_use_func_safepoints(-1)
  self.jit_module.gc_set_root_scratch([]) |> ignore
}

///|
fn JITCallContinuation::finish_error(
  self : JITCallContinuation,
  error : JITTrap,
) -> Unit raise JITTrap {
  self.finish(AttachedFrame)
  match error {
    JITTrap(msg) => {
      let report = self.jit_module.build_trap_report(msg)
      self.jit_module.last_trap_report = Some(report)
      raise JITTrap(@wasmoon_jit.format_trap_report_message(report))
    }
    JITNativeFiberFailure(message) => raise JITNativeFiberFailure(message)
    JITExit(code) => raise JITExit(code)
    JITResourceLimit(kind) => raise JITResourceLimit(kind)
    JITCancelled => raise JITCancelled
  }
}

///|
fn JITCallContinuation::advance(
  self : JITCallContinuation,
  retry_hostcall : Bool,
) -> JITContinuationOutcome raise JITTrap {
  if !self.active[0] {
    raise JITTrap("native JIT continuation is no longer active")
  }
  if self.first_entry[0] {
    self.jit_module.begin_call_gc(self.func.func_idx, self.entry_roots)
    self.gc_frame_active[0] = true
    self.first_entry[0] = false
  }
  let mut call_error : JITTrap? = None
  let event = self.call.advance(retry_hostcall) catch {
    error => {
      call_error = Some(error)
      Suspended(HostCall)
    }
  }
  self.jit_module.gc_use_func_safepoints(-1)
  self.jit_module.gc_set_root_scratch([]) |> ignore
  if self.jit_module.context is None {
    match (call_error, event) {
      (Some(_), _) | (None, Returned(_)) => self.finish(AttachedFrame)
      (None, Suspended(_)) => {
        self.call.cancel()
        self.finish(DetachedFrameReleased)
      }
    }
    raise JITTrap("native JIT context disappeared while suspended")
  }
  if call_error is Some(error) {
    self.finish_error(error)
  }
  match event {
    Suspended(reason) => JITSuspended(reason, self)
    Returned(results) => {
      self.finish(AttachedFrame)
      JITReturned(results)
    }
  }
}

///|
/// Enter a native JIT function on a resumable fiber.
pub fn JITModule::start_continuation_call(
  self : JITModule,
  func : JITFunction,
  args : Array[Int64],
) -> JITContinuationOutcome raise JITTrap {
  guard self.context is Some(ctx) else { return JITReturned([]) }
  self.last_trap_report = None
  let call = ctx.start_continuation(
    func.func_ptr,
    args,
    func.param_types,
    func.result_types,
  )
  let continuation : JITCallContinuation = {
    jit_module: self,
    func,
    call,
    entry_roots: @wasmoon_jit.collect_gc_root_args(args, func.param_types),
    first_entry: [true],
    gc_frame_active: [false],
    active: [true],
  }
  continuation.advance(false)
}

///|
/// Resume after the component scheduler has made the suspended host operation
/// runnable. Only that hostcall is retried; the guest frame itself is retained.
pub fn JITCallContinuation::continue_execution(
  self : JITCallContinuation,
) -> JITContinuationOutcome raise JITTrap {
  self.advance(true)
}

///|
/// Release a parked native JIT call without resuming it.
pub fn JITCallContinuation::cancel(
  self : JITCallContinuation,
) -> Unit raise JITTrap {
  if !self.active[0] {
    return
  }
  self.call.cancel()
  self.finish(DetachedFrameReleased)
}

///|
/// Structured result for a cooperative JIT invocation.
pub(all) enum JITCallResult {
  Completed(Array[Int64])
  Cancelled
  Failed(JITTrap)
  UnsupportedCancellation
  TimedOut
  InvalidTimeout
} derive(Debug)

///|
/// Invoke JIT code with an invocation-local cooperative cancellation callback.
/// Instrumented code polls at Wasm function entries and loop headers. Blocking
/// host functions are not interrupted while they run.
pub fn JITModule::call_with_context_controlled(
  self : JITModule,
  func : JITFunction,
  args : Array[Int64],
  cancel~ : (() -> Bool)? = None,
  timeout_ms~ : Int32? = None,
) -> JITCallResult {
  guard @wasmoon_jit.InvocationControl::new(timeout_ms, cancel) is Some(control) else {
    return InvalidTimeout
  }
  let controlled = cancel is Some(_) || timeout_ms is Some(_)
  if controlled && !self.cancellation_safepoints {
    return UnsupportedCancellation
  }
  if control.poll() {
    return if control.expired() { TimedOut } else { Cancelled }
  }
  match self.context {
    None => Completed([])
    Some(ctx) => {
      if controlled {
        ctx.set_cancellation_callback(() => control.poll())
      }
      defer (if controlled { ctx.clear_cancellation_callback() })
      try self.call_with_context(func, args) catch {
        JITCancelled => if control.expired() { TimedOut } else { Cancelled }
        error => Failed(error)
      } noraise {
        values => if control.expired() { TimedOut } else { Completed(values) }
      }
    }
  }
}

///|
fn JITModule::build_trap_report(
  self : JITModule,
  msg : String,
) -> @wasmoon_jit.TrapReport {
  let details = @wasmoon_jit.get_last_trap_details()
  let mut wasm_func_idx : Int32? = None
  let mut wasm_func_name : String? = None
  let mut wasm_offset : Int64? = None
  let mut native_offset : Int64? = None
  let wasm_frames : Array[@wasmoon_jit.WasmTrapFrame] = []
  let signal_name = if details.signal != 0 {
    @wasmoon_jit.format_signal_name(details.signal)
  } else {
    ""
  }

  fn add_unique_frame(
    frames : Array[@wasmoon_jit.WasmTrapFrame],
    frame : @wasmoon_jit.WasmTrapFrame,
  ) -> Unit {
    for existing in frames {
      if existing.func_idx == frame.func_idx &&
        existing.pc == frame.pc &&
        existing.wasm_offset == frame.wasm_offset {
        return
      }
    }
    frames.push(frame)
  }

  match self.find_func_by_pc(details.pc) {
    Some((func_idx, f, offset)) => {
      wasm_func_idx = Some(func_idx)
      wasm_func_name = Some(f.name)
      wasm_offset = f.wasm_offset(offset)
      native_offset = Some(offset.to_int64())
      add_unique_frame(wasm_frames, {
        pc: details.pc,
        func_idx,
        func_name: f.name,
        wasm_offset,
        native_offset,
      })
    }
    None =>
      if details.func_idx >= 0 {
        wasm_func_idx = Some(details.func_idx)
        let name = match self.functions.get(details.func_idx) {
          Some(f) => f.name
          None => "func_\{details.func_idx}"
        }
        wasm_func_name = Some(name)
        wasm_offset = None
        if details.pc != 0L {
          add_unique_frame(wasm_frames, {
            pc: details.pc,
            func_idx: details.func_idx,
            func_name: name,
            wasm_offset: None,
            native_offset: None,
          })
        }
      }
  }

  let captured = @wasmoon_jit.get_last_trap_pcs()
  for i in 1..<captured.length() {
    // A return PC may equal a range's end. The preceding byte belongs to the
    // call instruction on both supported targets. Preserve recursive repeats.
    let pc = captured[i] - 1L
    if self.find_func_by_pc(pc) is Some((func_idx, function_, offset)) {
      wasm_frames.push({
        pc,
        func_idx,
        func_name: function_.name,
        wasm_offset: function_.wasm_offset(offset),
        native_offset: Some(offset.to_int64()),
      })
    }
  }
  let caller_func_idx = if wasm_frames.length() > 1 {
    Some(wasm_frames[1].func_idx)
  } else {
    None
  }

  let mut dump_path : String? = None
  if wasm_func_idx is Some(func_idx) &&
    self.debug_db is Some(db) &&
    db.get(func_idx) is Some(dbg) {
    let name = match self.functions.get(func_idx) {
      Some(f) => f.name
      None => "func\{func_idx}"
    }
    let path = "target/jit-trap-\{func_idx}-\{@wasmoon_jit.sanitize_debug_filename(name)}.log"
    let mut ctx_mem0_ptr = 0L
    let mut ctx_mem0_size = 0L
    match self.context {
      Some(ctx) => {
        ctx_mem0_ptr = ctx.get_memory_ptr(0)
        ctx_mem0_size = ctx.get_memory_size(0)
      }
      None => ()
    }
    let content = "func_idx: \{func_idx}\n" +
      "name: \{name}\n" +
      "signal: \{details.signal}\n" +
      "pc: \{@wasmoon_jit.format_u64_hex(details.pc)}\n" +
      "lr: \{@wasmoon_jit.format_u64_hex(details.lr)}\n" +
      "frame_lr: \{@wasmoon_jit.format_u64_hex(details.frame_lr)}\n" +
      "fault_addr: \{@wasmoon_jit.format_u64_hex(details.fault_addr)}\n" +
      "brk_imm: \{details.brk_imm}\n\n" +
      "ctx_mem0_ptr: \{@wasmoon_jit.format_u64_hex(ctx_mem0_ptr)}\n" +
      "ctx_mem0_size: \{ctx_mem0_size}\n\n" +
      "x0: \{@wasmoon_jit.format_u64_hex(details.x0)}\n" +
      "x1: \{@wasmoon_jit.format_u64_hex(details.x1)}\n" +
      "x2: \{@wasmoon_jit.format_u64_hex(details.x2)}\n" +
      "x3: \{@wasmoon_jit.format_u64_hex(details.x3)}\n" +
      "x6: \{@wasmoon_jit.format_u64_hex(details.x6)}\n" +
      "x7: \{@wasmoon_jit.format_u64_hex(details.x7)}\n" +
      "x8: \{@wasmoon_jit.format_u64_hex(details.x8)}\n" +
      "x9: \{@wasmoon_jit.format_u64_hex(details.x9)}\n" +
      "x10: \{@wasmoon_jit.format_u64_hex(details.x10)}\n" +
      "x11: \{@wasmoon_jit.format_u64_hex(details.x11)}\n" +
      "x15: \{@wasmoon_jit.format_u64_hex(details.x15)}\n\n" +
      "== MilkIR ==\n" +
      dbg.ir +
      "\n\n" +
      "== Target VCode ==\n" +
      dbg.target_vcode +
      "\n\n" +
      "== Allocated Target VCode ==\n" +
      dbg.allocated_vcode +
      "\n\n" +
      "== Machine Code ==\n" +
      dbg.machine_code +
      "\n"
    let content = match caller_func_idx {
      Some(caller_idx) =>
        match db.get(caller_idx) {
          Some(cdbg) => {
            let caller_name = match self.functions.get(caller_idx) {
              Some(f) => f.name
              None => "func_\{caller_idx}"
            }
            let caller_pc = if wasm_frames.length() > 1 {
              wasm_frames[1].pc
            } else {
              0L
            }
            content +
            "\n== Caller ==\n" +
            "caller_func_idx: \{caller_idx}\n" +
            "caller_name: \{caller_name}\n" +
            "caller_pc: \{@wasmoon_jit.format_u64_hex(caller_pc)}\n\n" +
            "== Caller MilkIR ==\n" +
            cdbg.ir +
            "\n\n" +
            "== Caller Target VCode ==\n" +
            cdbg.target_vcode +
            "\n\n" +
            "== Caller Allocated Target VCode ==\n" +
            cdbg.allocated_vcode +
            "\n\n" +
            "== Caller Machine Code ==\n" +
            cdbg.machine_code +
            "\n"
          }
          None => content
        }
      None => content
    }
    @fs.write_string_to_file(path, content) catch {
      _ => ()
    }
    dump_path = Some(path)
  }

  {
    trap_kind: msg,
    message: msg,
    signal: details.signal,
    signal_name,
    pc: details.pc,
    lr: details.lr,
    fp: details.fp,
    frame_lr: details.frame_lr,
    fault_addr: details.fault_addr,
    brk_imm: details.brk_imm,
    wasm_func_idx,
    wasm_func_name,
    wasm_offset,
    native_offset,
    wasm_frames,
    host_frames: [],
    dump_path,
  }
}

///|
/// Set memory0 for the JIT context
pub fn JITModule::set_memory(
  self : JITModule,
  mem0_ptr : @wasmoon_jit.MemoryDescriptor,
) -> Unit {
  if self.context is Some(ctx) {
    ctx.set_memory(mem0_ptr)
  }
}

///|
/// Get current memory base pointer for memidx
pub fn JITModule::get_memory_ptr(self : JITModule, memidx : Int32) -> Int64 {
  match self.context {
    Some(ctx) => ctx.get_memory_ptr(memidx)
    None => 0L
  }
}

///|
/// Get current memory size in bytes for memidx
pub fn JITModule::get_memory_size(self : JITModule, memidx : Int32) -> Int64 {
  match self.context {
    Some(ctx) => ctx.get_memory_size(memidx)
    None => 0L
  }
}

///|
/// Install a private table of borrowed runtime global-cell addresses.
pub fn JITModule::bind_globals(
  self : JITModule,
  globals : FixedArray[Int64],
) -> Int64 {
  match self.context {
    Some(ctx) => ctx.ctx.bind_globals(globals)
    None => 0L
  }
}

///|
/// Transfer a malloc-owned table of borrowed global-cell addresses.
/// Prefer bind_globals for MoonBit-owned input.
pub fn JITModule::set_globals(self : JITModule, globals_ptr : Int64) -> Unit {
  if self.context is Some(ctx) {
    ctx.set_globals(globals_ptr)
  }
}

///|
/// Set GC heap in the JIT context for inline allocation
/// This enables fast-path bump-pointer allocation in JIT-compiled code
pub fn JITModule::set_gc_heap(
  self : JITModule,
  heap_ptr : @wasmoon_jit.GCHeapHandle,
) -> Unit {
  if self.context is Some(context) {
    context.ctx.set_gc_heap_ptr(heap_ptr)
  }
}

///|
/// Push a GC frame node in current JIT context.
pub fn JITModule::gc_begin_frame(
  self : JITModule,
  frame_id : Int64,
) -> Unit raise JITTrap {
  guard self.context is Some(context) else {
    raise JITTrap("missing JIT context")
  }
  context.ctx.gc_begin_frame(frame_id) catch {
    _ => raise JITTrap("out of memory")
  }
}

///|
fn JITModule::begin_call_gc(
  self : JITModule,
  function : Int32,
  roots : Array[Int64],
) -> Unit raise JITTrap {
  guard self.gc_set_root_scratch(roots) else { raise JITTrap("out of memory") }
  errdefer {
    self.gc_use_func_safepoints(-1)
    self.gc_set_root_scratch([]) |> ignore
  }
  self.gc_use_func_safepoints(function)
  self.gc_begin_frame(function.to_int64())
}

///|
/// Pop a GC frame node in current JIT context.
pub fn JITModule::gc_end_frame(self : JITModule) -> Unit {
  if self.context is Some(context) {
    context.ctx.gc_end_frame()
  }
}

///|
/// Set context-local scratch roots for allocation retry collections.
pub fn JITModule::gc_set_root_scratch(
  self : JITModule,
  roots : Array[Int64],
) -> Bool {
  match self.context {
    Some(context) => context.ctx.gc_set_root_scratch(roots)
    None => false
  }
}

///|
/// Set safepoint metadata table pointer for current context.
pub fn JITModule::gc_set_safepoint_table(
  self : JITModule,
  table_ptr : Int64,
) -> Unit {
  if self.context is Some(context) {
    context.ctx.gc_set_safepoint_table(table_ptr)
  }
}

///|
/// Select currently active function safepoint table (`func_idx < 0` clears).
pub fn JITModule::gc_use_func_safepoints(
  self : JITModule,
  func_idx : Int32,
) -> Unit {
  if self.context is Some(context) {
    context.ctx.gc_use_func_safepoints(func_idx)
  }
}

///|
pub fn JITModule::throw_exception_tag(
  self : JITModule,
  tag_addr : Int32,
) -> Unit raise @wasmoon_jit.NativeSetupError {
  guard self.context is Some(context) else {
    raise InvalidBinding("missing JIT context")
  }
  context.ctx.throw_exception_tag(tag_addr)
}

///|
pub fn JITModule::throw_exception_values(
  self : JITModule,
  tag_addr : Int32,
  values : Array[Int64],
) -> Unit raise @wasmoon_jit.NativeSetupError {
  guard self.context is Some(context) else {
    raise InvalidBinding("missing JIT context")
  }
  context.ctx.throw_exception_values(tag_addr, values)
}

///|
pub fn JITModule::throw_store_exception_values(
  self : JITModule,
  tag_addr : Int32,
  values : Array[Int64],
) -> Unit raise @wasmoon_jit.NativeSetupError {
  guard self.context is Some(context) else {
    raise InvalidBinding("missing JIT context")
  }
  context.ctx.throw_store_exception_values(tag_addr, values)
}

///|
pub fn JITModule::setup_gc(
  self : JITModule,
  heap : @wasmoon_jit.CHeap,
  types : Array[@types.SubType],
  canonical_indices : Array[Int32],
  func_type_indices : Array[Int32],
) -> Unit raise @wasmoon_jit.GCSetupError {
  guard self.context is Some(context) else { raise MissingJITContext }
  context.ctx.setup_gc(heap, types, canonical_indices, func_type_indices)
}

///|
pub fn JITModule::setup_gc_with_func_table(
  self : JITModule,
  heap : @wasmoon_jit.CHeap,
  types : Array[@types.SubType],
  canonical_indices : Array[Int32],
  func_type_indices : Array[Int32],
  func_table_ptr : Int64,
  num_funcs : Int32,
) -> Unit raise @wasmoon_jit.GCSetupError {
  guard self.context is Some(context) else { raise MissingJITContext }
  context.ctx.setup_gc_with_func_table(
    heap, types, canonical_indices, func_type_indices, func_table_ptr, num_funcs,
  )
}

///|
pub fn JITModule::teardown_gc(self : JITModule) -> Unit {
  if self.context is Some(context) {
    context.ctx.teardown_gc()
  }
}

///|
pub fn JITModule::gc_environment_is_clear(self : JITModule) -> Bool {
  match self.context {
    Some(context) => context.ctx.gc_environment_is_clear()
    None => true
  }
}

///|
/// Allocate guarded memory with mmap for bounds check elimination
/// Memory is allocated with guard pages (PROT_NONE) after the accessible region
/// Access to guard pages triggers SIGSEGV which is caught and converted to a trap
/// This enables eliminating explicit bounds checks in JIT-compiled code
///
/// Parameters:
///   initial_pages: Initial memory size in WASM pages (64KB each)
///   max_pages: Maximum memory size in WASM pages (None = default 4GB reservation)
///
/// Returns: memory pointer on success, 0 on failure
pub fn JITModule::alloc_guarded_memory(
  self : JITModule,
  initial_pages : Int32,
  max_pages : Int32?,
) -> @wasmoon_jit.MemoryDescriptor {
  match self.context {
    Some(ctx) => ctx.alloc_guarded_memory(initial_pages, max_pages)
    None => @wasmoon_jit.MemoryDescriptor::null()
  }
}

///|
/// Set multiple memories for the JIT context (multi-memory support)
pub fn JITModule::set_memory_pointers(
  self : JITModule,
  memories : Array[@wasmoon_jit.MemoryInfo],
) -> Unit raise @wasmoon_jit.NativeSetupError {
  guard self.context is Some(ctx) else {
    raise InvalidBinding("missing JIT context")
  }
  ctx.set_memory_pointers(memories)
}

///|
/// Configure the guarded native-fiber stack used by JIT calls.
/// This records the size used by later invocations; allocation is deferred
/// until a native continuation starts. JIT-compiled Wasm code runs on a
/// separate stack,
/// providing controlled stack overflow behavior:
/// - Stack overflows hit a guard page and trigger "call stack exhausted" trap
/// - Host stack is protected from runaway WASM recursion
/// - Cross-platform consistent behavior
///
/// Parameters:
///   stack_size: Size of the stack in bytes (default: 1MB = 1048576)
///
/// Returns: true when the configuration was accepted.
#alias(alloc_wasm_stack, deprecated="Use configure_native_fiber_stack_size instead")
pub fn JITModule::configure_native_fiber_stack_size(
  self : JITModule,
  stack_size : Int64,
) -> Bool {
  match self.context {
    Some(ctx) => ctx.configure_native_fiber_stack_size(stack_size)
    None => false
  }
}

///|
/// Check if a native-fiber stack size has been configured.
#alias(has_wasm_stack, deprecated="Use has_configured_native_fiber_stack_size instead")
pub fn JITModule::has_configured_native_fiber_stack_size(
  self : JITModule,
) -> Bool {
  match self.context {
    Some(ctx) => ctx.has_configured_native_fiber_stack_size()
    None => false
  }
}

///|
/// Set the hostcall callback used for JIT -> host bridging.
pub fn JITModule::set_hostcall_callback(
  self : JITModule,
  callback : () -> @wasmoon_jit.NativeHostcallOutcome,
) -> Unit {
  if self.context is Some(ctx) {
    ctx.set_hostcall_callback(callback)
  }
}

///|
pub fn JITModule::clear_hostcall_callback(self : JITModule) -> Unit {
  if self.context is Some(ctx) {
    ctx.clear_hostcall_callback()
  }
}

///|
/// Initialize indirect table for call_indirect.
/// table_size: number of table elements
/// elem_init: array of (table_idx, func_idx, type_idx) triples
pub fn JITModule::init_indirect_table(
  self : JITModule,
  table_size : Int32,
  elem_init : Array[(Int32, Int32, Int32)],
) -> Unit {
  if self.context is Some(ctx) && ctx.alloc_indirect_table(table_size) {
    for entry in elem_init {
      let (table_idx, func_idx, type_idx) = entry
      ctx.set_indirect(table_idx, func_idx, type_idx)
    }
  }
}

// ============ Segment Setup/Teardown ============
// For memory.init, data.drop, table.init, elem.drop instructions

///|
/// Initialize per-context segment state for bulk memory/table and GC segment ops.
/// This persists with the JIT context until it is freed (wasmtime-style).
///
/// - data_dropped/elem_dropped: optional initial dropped flags (default false).
/// - elem_segments: each segment is a flattened Int64 array of pairs:
///     [val0, ty0, val1, ty1, ...] (len must be even).
pub fn JITModule::setup_segments(
  self : JITModule,
  datas : Array[@types.Data],
  elem_segments : Array[Array[Int64]],
  data_dropped~ : Array[Bool] = [],
  elem_dropped~ : Array[Bool] = [],
) -> Unit raise @wasmoon_jit.NativeSetupError {
  guard self.context is Some(ctx) else {
    raise InvalidBinding("missing JIT context")
  }
  ctx.ctx.setup_segments(datas, elem_segments, data_dropped~, elem_dropped~)
}

///|
/// Clear per-context segment state (frees owned segment buffers).
pub fn JITModule::clear_segments(self : JITModule) -> Unit {
  if self.context is Some(ctx) {
    ctx.ctx.clear_segments()
  }
}

///|
/// Initialize shared tables from Store (for multi-table support with table imports/exports).
/// jit_tables: Array of JITTable from Store (one per runtime table)
/// elem_init: Array of (table_idx, elem_idx, func_idx?, type_hash) tuples
pub fn JITModule::init_shared_tables(
  self : JITModule,
  jit_tables : Array[@wasmoon_jit.JITTable?],
  elem_init : Array[(Int32, Int32, Int32?, Int32)],
) -> Unit raise @wasmoon_jit.NativeSetupError {
  guard self.context is Some(ctx) else {
    raise InvalidBinding("missing JIT context")
  }
  // Validate all Store identities before publishing any initializer.
  let writes : Array[(@wasmoon_jit.JITTable, Int32, Int64, Int32)] = []
  for (table_idx, elem_idx, func_idx, type_hash) in elem_init {
    if table_idx < 0 || table_idx >= jit_tables.length() {
      continue
    }
    guard jit_tables[table_idx] is Some(table) else { continue }
    let value = match func_idx {
      None => @wasm_milkir.NULL_REF
      Some(index) =>
        if table.raw_ptr().uses_store_references() {
          guard index >= 0 &&
            index < self.store_functions.length() &&
            self.store_functions[index] >= 0 else {
            raise InvalidBinding("missing Store function identity")
          }
          @wasmoon_jit.encode_store_funcref(self.store_functions[index])
        } else {
          let pointer = self.get_func_ptr(index)
          if pointer == 0L {
            @wasmoon_jit.encode_funcref_idx(index)
          } else {
            @wasmoon_jit.tag_funcref_ptr(pointer)
          }
        }
    }
    writes.push((table, elem_idx, value, type_hash))
  }
  ctx.set_table_pointers(jit_tables)
  for (table, index, value, type_hash) in writes {
    table.set(index, value, type_hash)
  }
}

///|
/// Register DWARF debug info with the debugger (LLDB/GDB)
/// This enables stack traces to show WebAssembly function names
/// Retain the returned owner while debug metadata is needed.
/// Dropping its last reference unregisters it; destroy() closes it early.
/// verbose: if true, print debug info to stderr
pub fn JITModule::register_dwarf(
  self : JITModule,
  verbose~ : Bool = false,
) -> @wasmoon_jit.DWARFBuilder raise @wasmoon_jit.NativeSetupError {
  let dwarf = @wasmoon_jit.DWARFBuilder::DWARFBuilder()
  for range in self.address_ranges {
    let func = self.functions[range.func_idx]
    dwarf.add_function(func.name, range.start, func.code_size, range.func_idx)
  }
  if !self.address_ranges.is_empty() && !dwarf.register(verbose~) {
    raise DebugRegistrationFailed
  }
  dwarf
}

///|
pub fn JITModule::set_callable_types(
  self : JITModule,
  local_types : Array[Int32],
  parents : Array[Int32],
  entries : Array[(Int64, Int32)],
  tags : Array[Int32],
) -> Unit {
  if self.context is Some(context) {
    context.ctx.set_callable_types(local_types, parents, entries, tags)
  }
}

///|
pub fn JITModule::bind_callable_registry(
  self : JITModule,
  registry : @wasmoon_jit.NativeCallableRegistry,
  local_types : Array[Int32],
  tags : Array[Int32],
  functions~ : Array[Int32] = [],
) -> Unit {
  self.store_functions = functions.copy()
  if self.context is Some(context) {
    context.ctx.bind_callable_registry(registry, local_types, tags, functions~)
  }
}

///|
pub fn JITModule::has_callable_metadata(self : JITModule) -> Bool {
  match self.context {
    Some(context) => context.ctx.has_callable_metadata()
    None => false
  }
}

///|
/// Scheduling requires guest safepoints in the compiled artifact.
pub fn JITModule::set_cooperative_scheduling(
  self : JITModule,
  enabled : Bool,
  quantum~ : Int32 = 1024,
) -> Bool {
  if enabled && !self.cancellation_safepoints {
    return false
  }
  guard self.context is Some(context) else { return false }
  context.set_cooperative_scheduling(enabled, quantum)
}

///|
pub fn JITModule::set_exception_arena(
  self : JITModule,
  arena : @wasmoon_jit.NativeExceptionArena,
) -> Unit {
  if self.context is Some(context) {
    context.ctx.set_exception_arena(arena)
  }
}

///|
pub fn JITModule::prepare_continuations(
  self : JITModule,
  types : Array[@types.SubType],
  state : @wasmoon_jit.NativeExecutionState,
) -> Unit raise JITTrap {
  if self.context is Some(context) {
    context.ctx.set_continuation_arena(state.continuations())
    for index, type_ in types {
      if type_.composite is Cont(function_index) {
        guard types[function_index].composite is Func(signature) else {
          raise JITTrap("invalid continuation signature")
        }
        let trampoline = context.entry_trampoline(
          signature.params,
          signature.results,
        )
        if !context.ctx.define_continuation_type(
            index,
            trampoline,
            signature.params,
            signature.results,
          ) {
          raise JITTrap("continuation signature allocation failed")
        }
      }
    }
  }
}

///|
pub fn JITModule::bind_segment_drop_flags(
  self : JITModule,
  instance : @runtime.ModuleInstance,
) -> Unit {
  guard self.context is Some(ctx) else { return }
  instance.bind_native_segments(ctx.ctx)
}

///|
/// Install the captured Store policy for the next activation. Native activations
/// retain their own callback snapshot across parking and nested invocations.
pub fn JITModule::set_execution_scope(
  self : JITModule,
  scope : @runtime.ExecutionScope?,
) -> Bool {
  if scope is Some(_) && !self.cancellation_safepoints {
    return false
  }
  if self.context is Some(context) {
    match scope {
      Some(scope) => context.set_cancellation_callback(() => scope.poll())
      None => context.clear_cancellation_callback()
    }
  }
  true
}
