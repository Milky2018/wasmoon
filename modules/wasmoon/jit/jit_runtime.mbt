///|
/// JIT Execution Runtime
/// Loads and executes verified v9 JIT artifacts.

///|
/// JIT-compiled function ready for execution
pub struct JITFunction {
  func_idx : Int
  name : String
  priv func_ptr : Int64
  priv code_size : Int
  param_types : Array[@types.ValueType] // Parameter types for proper register allocation
  result_types : Array[@types.ValueType] // Return types (empty = void, 1 = single, 2+ = multi-value)
}

///|
/// Error when loading a precompiled JIT module
pub suberror JITModuleLoadError {
  ContextAllocationFailed(total_funcs~ : Int)
  UnsupportedImport(
    import_idx~ : Int,
    module_name~ : String,
    func_name~ : String
  )
  ImportTrampolineAllocationFailed(
    import_idx~ : Int,
    module_name~ : String,
    func_name~ : String,
    code_size~ : Int
  )
  ImportTrampolineCompilationFailed(
    import_idx~ : Int,
    module_name~ : String,
    func_name~ : String,
    message~ : String
  )
  ArtifactInstallationFailed(cause~ : @wasmoon_jit.JitInstallError)
  FunctionMetadataRegistrationFailed(func_idx~ : Int, message~ : String)
} derive(Debug)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for JITModuleLoadError with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
fn JITFunction::JITFunction(
  func_idx : Int,
  name : String,
  func_ptr : Int64,
  code_size : Int,
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> JITFunction {
  { func_idx, name, func_ptr, code_size, param_types, result_types, }
}

///|
/// Address range for PC-to-function mapping (sorted by start address)
struct AddressRange {
  start : Int64 // Function start address
  end : Int64 // Function end address (start + code_size)
  func_idx : Int // Wasm function index
} derive(Debug)

///|
/// Loaded precompiled module with executable functions
struct JITModule {
  functions : Map[Int, JITFunction]
  by_name : Map[String, Int]
  address_ranges : Array[AddressRange] // Sorted by start address for binary search
  mut context : JITContext?
  mut debug_db : @wasmoon_jit.JITDebugDB?
  mut last_trap_report : @wasmoon_jit.TrapReport?
  // Keep generated process-local import trampolines alive.
  owned_trampolines : Array[@wasmoon_jit.InstalledTrampoline]
  // Keep the transactionally installed artifact alive.
  mut installed_code : @wasmoon_jit.InstalledCode?
  mut wasi_stdout_callback : ((Bytes) -> Unit)?
  mut wasi_stderr_callback : ((Bytes) -> Unit)?
  mut cancellation_safepoints : Bool
}

///|
pub fn JITModule::JITModule() -> JITModule {
  {
    functions: Map([]),
    by_name: Map([]),
    address_ranges: [],
    context: None,
    debug_db: None,
    last_trap_report: None,
    owned_trampolines: [],
    installed_code: None,
    wasi_stdout_callback: None,
    wasi_stderr_callback: None,
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
  signature_count : Int,
) -> Int {
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
  function_index : Int,
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
) -> Map[String, Int64] raise JITModuleLoadError {
  let import_targets : Map[String, Int64] = Map([])
  let target = artifact_target_architecture(artifact)
  let trampoline_installer = @wasmoon_jit.JitCodeInstaller::new(fn(_) { None })
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
  function_names? : Array[String] = [],
  debug_db? : @wasmoon_jit.JITDebugDB? = None,
) -> JITModule raise JITModuleLoadError {
  JITModule::load_artifact_with_imports(
    loaded,
    func_signatures,
    Map([]),
    function_names~,
    debug_db~,
  )
}

///|
/// Load a verified v9 artifact with embedding-provided import addresses.
pub fn JITModule::load_artifact_with_imports(
  loaded : @wasmoon_jit.LoadedArtifact,
  func_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])],
  external_imports : Map[String, Map[String, Int64]],
  function_names? : Array[String] = [],
  debug_db? : @wasmoon_jit.JITDebugDB? = None,
) -> JITModule raise JITModuleLoadError {
  load_artifact_with_imports_using_registrar(
    loaded,
    func_signatures,
    external_imports,
    function_names,
    debug_db,
    fn(context, func_idx, safepoints) {
      context.register_safepoints(func_idx, safepoints)
    },
  )
}

///|
fn load_artifact_with_imports_using_registrar(
  loaded : @wasmoon_jit.LoadedArtifact,
  func_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])],
  external_imports : Map[String, Map[String, Int64]],
  function_names : Array[String],
  debug_db : @wasmoon_jit.JITDebugDB?,
  register_safepoints : (JITContext, Int, Array[@code_object.SafepointSite]) -> Bool,
) -> JITModule raise JITModuleLoadError {
  let artifact = loaded.artifact()
  let total_funcs = artifact_context_function_count(
    artifact,
    func_signatures.length(),
  )
  guard JITContext::try_alloc(total_funcs) is Some(ctx) else {
    raise ContextAllocationFailed(total_funcs~)
  }
  for function in artifact.functions {
    let identity = function.identity
    if !register_safepoints(ctx, identity.function_index, function.safepoints) {
      raise FunctionMetadataRegistrationFailed(
        func_idx=identity.function_index,
        message="failed to register GC safepoints",
      )
    }
  }
  let jit_module = JITModule::JITModule()
  let import_targets = stage_artifact_imports(
    artifact,
    func_signatures,
    external_imports,
    jit_module.owned_trampolines,
  )
  let runtime_symbols = @wasmoon_jit.RuntimeSymbolResolver::with_wasmoon_runtime_symbols()
  let installer = @wasmoon_jit.JitCodeInstaller::new(fn(target) {
    match target {
      External(symbol) =>
        match import_targets.get(symbol.name) {
          Some(pointer) => Some(pointer)
          None => runtime_symbols.resolve(symbol.name)
        }
      Code(_) | Data(_) => None
    }
  })
  let installed = installer.install(loaded) catch {
    error => raise ArtifactInstallationFailed(cause=error)
  }
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
        param_types,
        result_types,
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
  if self.context is Some(context) {
    context.close()
  }
  self.context = None
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
pub fn JITModule::get_func_count(self : JITModule) -> Int {
  match self.context {
    Some(context) => context.ctx.func_count()
    None => 0
  }
}

///|
/// Refresh one Store-owned table from the context that borrowed it.
pub fn JITModule::refresh_table_layout(
  self : JITModule,
  table_idx : Int,
) -> Bool {
  match self.context {
    Some(context) => context.refresh_table_layout(table_idx)
    None => false
  }
}

///|
/// Get a function by index
pub fn JITModule::get_func(self : JITModule, func_idx : Int) -> JITFunction? {
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
pub fn JITModule::get_func_ptr(self : JITModule, func_idx : Int) -> Int64 {
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
/// (func_idx, function, offset_in_function_bytes)
/// Uses binary search on sorted address_ranges for O(log n) lookup.
pub fn JITModule::find_func_by_pc(
  self : JITModule,
  pc : Int64,
) -> (Int, JITFunction, Int)? {
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
      self.gc_set_root_scratch(frame_roots) |> ignore
      self.gc_use_func_safepoints(func.func_idx)
      self.gc_begin_frame(func.func_idx.to_int64())
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
      self.flush_wasi_output(ctx)
      match call_error {
        Some(JITTrap(msg)) => {
          let report = self.build_trap_report(msg)
          self.last_trap_report = Some(report)
          raise JITTrap(@wasmoon_jit.format_trap_report_message(report))
        }
        Some(JITExit(code)) => raise JITExit(code)
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
  JITSuspended(JITCallContinuation)
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
    JITExit(code) => raise JITExit(code)
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
    self.jit_module.gc_set_root_scratch(self.entry_roots) |> ignore
    self.jit_module.gc_use_func_safepoints(self.func.func_idx)
    self.jit_module.gc_begin_frame(self.func.func_idx.to_int64())
    self.gc_frame_active[0] = true
    self.first_entry[0] = false
  }
  let mut call_error : JITTrap? = None
  let event = self.call.advance(retry_hostcall) catch {
    error => {
      call_error = Some(error)
      Suspended
    }
  }
  self.jit_module.gc_use_func_safepoints(-1)
  self.jit_module.gc_set_root_scratch([]) |> ignore
  self.jit_module.flush_wasi_output(
    match self.jit_module.context {
      Some(ctx) => ctx
      None => {
        match (call_error, event) {
          (Some(_), _) | (None, Returned(_)) => self.finish(AttachedFrame)
          (None, Suspended) => {
            self.call.cancel()
            self.finish(DetachedFrameReleased)
          }
        }
        raise JITTrap("native JIT context disappeared while suspended")
      }
    },
  )
  if call_error is Some(error) {
    self.finish_error(error)
  }
  match event {
    Suspended => JITSuspended(self)
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
} derive(Debug)

///|
/// Invoke JIT code with an invocation-local cooperative cancellation callback.
/// Instrumented code polls at Wasm function entries and loop headers. Blocking
/// host functions are not interrupted while they run.
pub fn JITModule::call_with_context_controlled(
  self : JITModule,
  func : JITFunction,
  args : Array[Int64],
  cancel? : (() -> Bool)? = None,
) -> JITCallResult {
  if cancel is Some(_) && !self.cancellation_safepoints {
    return UnsupportedCancellation
  }
  match self.context {
    None => Completed([])
    Some(ctx) => {
      if cancel is Some(callback) {
        ctx.set_cancellation_callback(callback)
      }
      let result = try self.call_with_context(func, args) catch {
        JITCancelled => Cancelled
        error => Failed(error)
      } noraise {
        values => Completed(values)
      }
      if cancel is Some(_) {
        ctx.clear_cancellation_callback()
      }
      result
    }
  }
}

///|
/// Flush captured WASI stdout/stderr into callbacks (if configured)
fn JITModule::flush_wasi_output(self : JITModule, ctx : JITContext) -> Unit {
  if self.wasi_stdout_callback is Some(cb) {
    let out = ctx.take_wasi_stdout()
    if out.length() > 0 {
      cb(out)
    }
  }
  if self.wasi_stderr_callback is Some(cb) {
    let out = ctx.take_wasi_stderr()
    if out.length() > 0 {
      cb(out)
    }
  }
}

///|
fn JITModule::build_trap_report(
  self : JITModule,
  msg : String,
) -> @wasmoon_jit.TrapReport {
  let details = @wasmoon_jit.get_last_trap_details()
  let mut wasm_func_idx : Int? = None
  let mut wasm_func_name : String? = None
  let mut wasm_offset : Int64? = None
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
      wasm_offset = Some(offset.to_int64())
      add_unique_frame(wasm_frames, {
        pc: details.pc,
        func_idx,
        func_name: f.name,
        wasm_offset: offset.to_int64(),
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
        wasm_offset = Some(0L)
        if details.pc != 0L {
          add_unique_frame(wasm_frames, {
            pc: details.pc,
            func_idx: details.func_idx,
            func_name: name,
            wasm_offset: 0L,
          })
        }
      }
  }

  let mut caller_func_idx : Int? = None
  if details.frame_lr != 0L {
    let mut caller_pc = details.frame_lr
    match self.find_func_by_pc(details.frame_lr) {
      Some((func_idx, f, offset)) => {
        caller_func_idx = Some(func_idx)
        add_unique_frame(wasm_frames, {
          pc: details.frame_lr,
          func_idx,
          func_name: f.name,
          wasm_offset: offset.to_int64(),
        })
      }
      None =>
        if details.frame_lr >= 4L {
          let lr_prev = details.frame_lr - 4L
          match self.find_func_by_pc(lr_prev) {
            Some((func_idx, f, offset)) => {
              caller_pc = lr_prev
              caller_func_idx = Some(func_idx)
              add_unique_frame(wasm_frames, {
                pc: caller_pc,
                func_idx,
                func_name: f.name,
                wasm_offset: offset.to_int64(),
              })
            }
            None => ()
          }
        }
    }
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
      "== IR ==\n" +
      dbg.ir +
      "\n\n" +
      "== MachV (before regalloc) ==\n" +
      dbg.machv_before_regalloc +
      "\n\n" +
      "== MachV (after regalloc) ==\n" +
      dbg.machv_after_regalloc +
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
            "== Caller IR ==\n" +
            cdbg.ir +
            "\n\n" +
            "== Caller MachV (before regalloc) ==\n" +
            cdbg.machv_before_regalloc +
            "\n\n" +
            "== Caller MachV (after regalloc) ==\n" +
            cdbg.machv_after_regalloc +
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
    wasm_frames,
    host_frames: [],
    dump_path,
  }
}

///|
/// Set memory0 for the JIT context
pub fn JITModule::set_memory(self : JITModule, mem0_ptr : Int64) -> Unit {
  if self.context is Some(ctx) {
    ctx.set_memory(mem0_ptr)
  }
}

///|
/// Get current memory base pointer for memidx
pub fn JITModule::get_memory_ptr(self : JITModule, memidx : Int) -> Int64 {
  match self.context {
    Some(ctx) => ctx.get_memory_ptr(memidx)
    None => 0L
  }
}

///|
/// Get current memory size in bytes for memidx
pub fn JITModule::get_memory_size(self : JITModule, memidx : Int) -> Int64 {
  match self.context {
    Some(ctx) => ctx.get_memory_size(memidx)
    None => 0L
  }
}

///|
/// Set globals array for the JIT context
pub fn JITModule::set_globals(self : JITModule, globals_ptr : Int64) -> Unit {
  if self.context is Some(ctx) {
    ctx.set_globals(globals_ptr)
  }
}

///|
/// Set GC heap in the JIT context for inline allocation
/// This enables fast-path bump-pointer allocation in JIT-compiled code
pub fn JITModule::set_gc_heap(self : JITModule, heap_ptr : Int64) -> Unit {
  if self.context is Some(context) {
    context.ctx.set_gc_heap_ptr(heap_ptr)
  }
}

///|
/// Push a GC frame node in current JIT context.
pub fn JITModule::gc_begin_frame(self : JITModule, frame_id : Int64) -> Unit {
  if self.context is Some(context) {
    context.ctx.gc_begin_frame(frame_id)
  }
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
  func_idx : Int,
) -> Unit {
  if self.context is Some(context) {
    context.ctx.gc_use_func_safepoints(func_idx)
  }
}

///|
pub fn JITModule::throw_exception_tag(self : JITModule, tag_addr : Int) -> Unit {
  if self.context is Some(context) {
    context.ctx.throw_exception_tag(tag_addr)
  }
}

///|
pub fn JITModule::throw_exception_values(
  self : JITModule,
  tag_addr : Int,
  values : Array[Int64],
) -> Unit {
  if self.context is Some(context) {
    context.ctx.throw_exception_values(tag_addr, values)
  }
}

///|
pub fn JITModule::setup_gc(
  self : JITModule,
  heap : @wasmoon_jit.CHeap,
  types : Array[@types.SubType],
  canonical_indices : Array[Int],
  func_type_indices : Array[Int],
) -> Unit raise @wasmoon_jit.GCSetupError {
  guard self.context is Some(context) else { raise MissingJITContext }
  context.ctx.setup_gc(heap, types, canonical_indices, func_type_indices)
}

///|
pub fn JITModule::setup_gc_with_func_table(
  self : JITModule,
  heap : @wasmoon_jit.CHeap,
  types : Array[@types.SubType],
  canonical_indices : Array[Int],
  func_type_indices : Array[Int],
  func_table_ptr : Int64,
  num_funcs : Int,
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
  initial_pages : Int,
  max_pages : Int?,
) -> Int64 {
  match self.context {
    Some(ctx) => ctx.alloc_guarded_memory(initial_pages, max_pages)
    None => 0L
  }
}

///|
/// Set multiple memories for the JIT context (multi-memory support)
pub fn JITModule::set_memory_pointers(
  self : JITModule,
  memories : Array[@wasmoon_jit.MemoryInfo],
) -> Unit {
  if self.context is Some(ctx) {
    ctx.set_memory_pointers(memories)
  }
}

///|
/// Configure the guarded native-fiber stack used by JIT calls.
/// When enabled, JIT-compiled Wasm code runs on a separate stack,
/// providing controlled stack overflow behavior:
/// - Stack overflows hit a guard page and trigger "call stack exhausted" trap
/// - Host stack is protected from runaway WASM recursion
/// - Cross-platform consistent behavior
///
/// Parameters:
///   stack_size: Size of the stack in bytes (default: 1MB = 1048576)
///
/// Returns: true when the requested size is valid.
pub fn JITModule::alloc_wasm_stack(
  self : JITModule,
  stack_size : Int64,
) -> Bool {
  match self.context {
    Some(ctx) => ctx.alloc_wasm_stack(stack_size)
    None => false
  }
}

///|
/// Check if a native-fiber stack size has been configured.
pub fn JITModule::has_wasm_stack(self : JITModule) -> Bool {
  match self.context {
    Some(ctx) => ctx.has_wasm_stack()
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
/// Initialize WASI context for JIT execution
/// args: command-line arguments
/// env: environment variables (KEY=VALUE format)
/// preopens: preopened directories as (host_path, guest_path) pairs
pub fn JITModule::init_wasi(
  self : JITModule,
  args : Array[String],
  env : Array[String],
  preopens : Array[(String, String)],
) -> Unit {
  if self.context is Some(ctx) {
    self.wasi_stdout_callback = None
    self.wasi_stderr_callback = None
    ctx.init_wasi(args, env, preopens)
  }
}

///|
/// Initialize WASI context with custom stdio handling
pub fn JITModule::init_wasi_with_stdio(
  self : JITModule,
  args : Array[String],
  env : Array[String],
  preopens : Array[(String, String)],
  stdout : ((Bytes) -> Unit)?,
  stderr : ((Bytes) -> Unit)?,
  stdin_data : Bytes?,
  stdin_callback? : (() -> Bytes)? = None,
) -> Unit {
  self.init_wasi(args, env, preopens)
  if self.context is Some(ctx) {
    match stdout {
      Some(cb) => {
        self.wasi_stdout_callback = Some(cb)
        ctx.set_wasi_stdout_capture(true)
      }
      None => ctx.set_wasi_stdout_capture(false)
    }
    match stderr {
      Some(cb) => {
        self.wasi_stderr_callback = Some(cb)
        ctx.set_wasi_stderr_capture(true)
      }
      None => ctx.set_wasi_stderr_capture(false)
    }
    match stdin_callback {
      Some(cb) => ctx.set_wasi_stdin_callback(cb)
      None => {
        ctx.clear_wasi_stdin_callback()
        match stdin_data {
          Some(data) => ctx.set_wasi_stdin_buffer(data)
          None => ctx.clear_wasi_stdin_buffer()
        }
      }
    }
  }
}

///|
/// Initialize WASI context with stdout/stderr redirected to /dev/null (for testing)
pub fn JITModule::init_wasi_quiet(
  self : JITModule,
  args : Array[String],
  env : Array[String],
  preopens : Array[(String, String)],
) -> Unit {
  if self.context is Some(ctx) {
    self.wasi_stdout_callback = None
    self.wasi_stderr_callback = None
    ctx.init_wasi_quiet(args, env, preopens)
  }
}

///|
/// Initialize indirect table for call_indirect.
/// table_size: number of table elements
/// elem_init: array of (table_idx, func_idx, type_idx) triples
pub fn JITModule::init_indirect_table(
  self : JITModule,
  table_size : Int,
  elem_init : Array[(Int, Int, Int)],
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
  data_dropped? : Array[Bool] = [],
  elem_dropped? : Array[Bool] = [],
) -> Unit {
  guard self.context is Some(ctx) else { return }
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
  elem_init : Array[(Int, Int, Int?, Int)],
) -> Unit {
  if self.context is None {
    return
  }
  let ctx = match self.context {
    Some(c) => c
    None => return
  }
  // Set up context to use the shared tables
  ctx.set_table_pointers(jit_tables)
  // Initialize table elements directly in the shared tables
  for entry in elem_init {
    let (table_idx, elem_idx, func_idx, type_hash) = entry
    // Get the JIT table
    if table_idx < 0 || table_idx >= jit_tables.length() {
      continue
    }
    let jit_table = match jit_tables[table_idx] {
      Some(tbl) => tbl
      None => continue
    }
    let funcref_value = match func_idx {
      Some(idx) => {
        let ptr = self.get_func_ptr(idx)
        if ptr == 0L {
          // Keep ref.func semantics even when this local function is not
          // currently compiled into a concrete machine-code pointer.
          @wasmoon_jit.encode_funcref_idx(idx)
        } else {
          @wasmoon_jit.tag_funcref_ptr(ptr)
        }
      }
      None => @wasm_milkir.NULL_REF
    }

    // Set the table entry (including null references)
    jit_table.set(elem_idx, funcref_value, type_hash)
  }
}

///|
/// Register DWARF debug info with the debugger (LLDB/GDB)
/// This enables stack traces to show WebAssembly function names
/// Returns the DWARFBuilder handle (call destroy() when done)
/// verbose: if true, print debug info to stderr
pub fn JITModule::register_dwarf(
  self : JITModule,
  verbose? : Bool = false,
) -> @wasmoon_jit.DWARFBuilder {
  let dwarf = @wasmoon_jit.DWARFBuilder::DWARFBuilder()
  for func_idx, func in self.functions {
    let addr = self.get_func_ptr(func_idx)
    dwarf.add_function(func.name, addr, func.code_size, func_idx)
  }
  dwarf.register(verbose~)
  dwarf
}
