///|
/// JIT Execution Runtime
/// Loads and executes precompiled .cwasm files

///|
/// JIT-compiled function ready for execution
pub struct JITFunction {
  func_idx : Int
  name : String
  priv exec_code : @wasmoon_jit.ExecCode
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
  FunctionCodeAllocationFailed(
    func_idx~ : Int,
    func_name~ : String,
    code_size~ : Int
  )
} derive(Debug)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for JITModuleLoadError with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(to_repr(self).to_string()))
}

///|
fn JITFunction::new(
  func_idx : Int,
  name : String,
  exec_code : @wasmoon_jit.ExecCode,
  code_size : Int,
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> JITFunction {
  { func_idx, name, exec_code, code_size, param_types, result_types }
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
  mut context_ptr : Int64
  mut debug_db : @wasmoon_jit.JITDebugDB?
  mut last_trap_report : @wasmoon_jit.TrapReport?
  // Keep generated import trampolines alive (GC-managed executable memory).
  import_exec_codes : Array[@wasmoon_jit.ExecCode]
  // Pseudo direct-call function indices -> near stub entry points.
  direct_call_targets : Map[Int, Int64]
  mut wasi_stdout_callback : ((Bytes) -> Unit)?
  mut wasi_stderr_callback : ((Bytes) -> Unit)?
}

///|
pub fn JITModule::new() -> JITModule {
  {
    functions: Map([]),
    by_name: Map([]),
    address_ranges: [],
    context: None,
    context_ptr: 0L,
    debug_db: None,
    last_trap_report: None,
    import_exec_codes: [],
    direct_call_targets: {},
    wasi_stdout_callback: None,
    wasi_stderr_callback: None,
  }
}

///|
fn install_direct_call_stubs(
  jit_module : JITModule,
  target : @cwasm.TargetArch,
) -> Unit raise JITModuleLoadError {
  let stubs = @wasmoon_jit.install_direct_call_stubs_for_target(target) catch {
    UnsupportedDirectCallStubTarget(pseudo_idx~, code_size~) =>
      raise ImportTrampolineAllocationFailed(
        import_idx=-1,
        module_name="__jit_direct_call",
        func_name="idx_\{pseudo_idx}",
        code_size~,
      )
    DirectCallStubAllocationFailed(pseudo_idx~, code_size~) =>
      raise ImportTrampolineAllocationFailed(
        import_idx=-1,
        module_name="__jit_direct_call",
        func_name="idx_\{pseudo_idx}",
        code_size~,
      )
  }
  for exec_code in stubs.exec_codes {
    jit_module.import_exec_codes.push(exec_code)
  }
  for entry in stubs.targets.iter() {
    let (pseudo_idx, ptr) = entry
    jit_module.direct_call_targets.set(pseudo_idx, ptr)
  }
}

///|
fn apply_func_addr_fixups(
  ctx : JITContext,
  jit_module : JITModule,
  precompiled : @cwasm.PrecompiledModule,
) -> Unit {
  let func_table_ptr = ctx.get_func_table_ptr()
  for entry in precompiled.functions {
    if entry.func_addr_fixups.length() == 0 {
      continue
    }
    if jit_module.functions.get(entry.func_idx) is Some(func) {
      let exec_ptr = func.exec_code.ptr()
      @wasmoon_jit.patch_func_addr_fixups_for_target(
        precompiled.target,
        exec_ptr,
        entry.func_addr_fixups,
        func_table_ptr,
      )
    }
  }
}

///|
fn apply_call_fixups(
  ctx : JITContext,
  jit_module : JITModule,
  precompiled : @cwasm.PrecompiledModule,
) -> Unit {
  for entry in precompiled.functions {
    for fixup in entry.call_fixups {
      if fixup.func_idx < 0 &&
        jit_module.direct_call_targets.get(fixup.func_idx) is None {
        if @wasmoon_jit.resolve_runtime_func_fixup_idx(fixup.func_idx)
          is Some(ptr) {
          jit_module.direct_call_targets.set(fixup.func_idx, ptr)
        }
      }
    }
  }
  let func_table_ptr = ctx.get_func_table_ptr()
  if func_table_ptr == 0L && jit_module.direct_call_targets.is_empty() {
    return
  }
  for entry in precompiled.functions {
    if entry.call_fixups.length() == 0 {
      continue
    }
    if jit_module.functions.get(entry.func_idx) is Some(func) {
      let exec_ptr = func.exec_code.ptr()
      @wasmoon_jit.patch_call_fixups_for_target(
        precompiled.target,
        exec_ptr,
        entry.call_fixups,
        func_table_ptr,
        jit_module.direct_call_targets,
      )
    }
  }
}

///|
/// Load a precompiled module
/// func_signatures: Array of (param_types, result_types) for each func_idx
pub fn JITModule::load(
  precompiled : @cwasm.PrecompiledModule,
  func_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])],
  debug_db? : @wasmoon_jit.JITDebugDB? = None,
) -> JITModule raise JITModuleLoadError {
  JITModule::load_with_imports(precompiled, func_signatures, {}, debug_db~)
}

///|
/// Load a precompiled module with external import resolution
/// func_signatures: Array of (param_types, result_types) for each func_idx
/// external_imports: Map from (module_name, func_name) to function pointer
pub fn JITModule::load_with_imports(
  precompiled : @cwasm.PrecompiledModule,
  func_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])],
  external_imports : Map[String, Map[String, Int64]],
  debug_db? : @wasmoon_jit.JITDebugDB? = None,
) -> JITModule raise JITModuleLoadError {
  let jit_module = JITModule::new()
  let total_funcs = @wasmoon_jit.required_context_function_count(
    precompiled,
    func_signatures.length(),
  )

  // Create JIT context with function table
  let context = JITContext::new(total_funcs)
  match context {
    None => raise ContextAllocationFailed(total_funcs~)
    Some(ctx) => {
      let context_ptr = ctx.ptr()
      // Context pointer must be visible before loading functions because
      // gc_set_func_safepoints() installs per-function tables during this phase.
      jit_module.context_ptr = context_ptr

      // Install near stubs used by pseudo direct-call fixups.
      install_direct_call_stubs(jit_module, precompiled.target)

      // Step 1: Populate import trampolines into function table
      for i, imp in precompiled.imports {
        // First check external imports, then fall back to built-in trampolines.
        let func_ptr = @wasmoon_jit.resolve_import_function_ptr(
          external_imports,
          imp.module_name,
          imp.func_name,
        )
        match func_ptr {
          Some(ptr) =>
            if ptr < 0L {
              // Special encoding: negative values represent a runtime Store host func address.
              // This allows callers to pass host funcs through `external_imports` without
              // exposing raw function pointers.
              let host_func_addr = (-(ptr + 1L)).to_int()
              let isa = @wasmoon_jit.target_arch_to_isa(precompiled.target)
              let (param_types, result_types) = if i < func_signatures.length() {
                func_signatures[i]
              } else {
                ([], [])
              }
              let mc = @wasmoon_jit.emit_hostcall_import_trampoline(
                param_types,
                result_types,
                host_func_addr,
                @wasmoon_jit.runtime_hostcall_symbol(),
                @wasmoon_jit.wasm_calling_convention(isa~),
                isa~,
              )
              let code_ints = mc.get_bytes()
              let exec = @wasmoon_jit.ExecCode::new(code_ints)
              match exec {
                Some(ec) => {
                  // AArch64 hostcall trampolines may carry runtime func-address
                  // fixups (LoadJITFuncPtr). Patch them before first execution.
                  let func_table_ptr = ctx.get_func_table_ptr()
                  for fixup in mc.get_func_addr_fixups() {
                    let func_idx = match
                      @wasmoon_jit.machv_reloc_target_to_cwasm_func_idx(
                        fixup.target,
                      ) {
                      Some(idx) => idx
                      None =>
                        abort(
                          "cannot patch hostcall trampoline target: \{fixup.target}",
                        )
                    }
                    @wasmoon_jit.patch_func_addr_fixup_raw_for_target(
                      precompiled.target,
                      ec.ptr(),
                      fixup.offset,
                      fixup.reg,
                      func_idx,
                      func_table_ptr,
                    )
                  }
                  jit_module.import_exec_codes.push(ec)
                  ctx.set_func(i, ec.ptr())
                }
                None =>
                  raise ImportTrampolineAllocationFailed(
                    import_idx=i,
                    module_name=imp.module_name,
                    func_name=imp.func_name,
                    code_size=code_ints.length(),
                  )
              }
            } else {
              ctx.set_func(i, ptr)
            }
          None =>
            raise UnsupportedImport(
              import_idx=i,
              module_name=imp.module_name,
              func_name=imp.func_name,
            )
        }
      }

      // Expose context before loading functions so per-function safepoint tables
      // can be installed during this phase.
      jit_module.context = Some(ctx)
      jit_module.context_ptr = context_ptr
      jit_module.debug_db = debug_db

      // Step 2: Load compiled functions and populate their pointers
      for entry in precompiled.functions {
        // Allocate executable memory directly from code array
        let exec_code = @wasmoon_jit.ExecCode::new(entry.code)
        match exec_code {
          Some(ec) => {
            // Get function signature
            let (param_types, result_types) = if entry.func_idx <
              func_signatures.length() {
              func_signatures[entry.func_idx]
            } else {
              ([], [])
            }
            let jit_func = JITFunction::new(
              entry.func_idx,
              entry.name,
              ec,
              entry.code.length(),
              param_types,
              result_types,
            )
            jit_module.functions.set(entry.func_idx, jit_func)
            jit_module.by_name.set(entry.name, entry.func_idx)
            // Set function pointer in context's function table
            ctx.set_func(entry.func_idx, ec.ptr())
            // Install per-function GC safepoint metadata (if present).
            jit_module.gc_set_func_safepoints(
              entry.func_idx,
              entry.gc_safepoints,
              entry.gc_stackmap_blob,
            )
            |> ignore
          }
          None =>
            raise FunctionCodeAllocationFailed(
              func_idx=entry.func_idx,
              func_name=entry.name,
              code_size=entry.code.length(),
            )
        }
      }

      // Patch direct-call function address loads now that pointers are known.
      apply_func_addr_fixups(ctx, jit_module, precompiled)
      apply_call_fixups(ctx, jit_module, precompiled)

      // Build sorted address_ranges for binary search in find_func_by_pc
      for func_idx, f in jit_module.functions {
        let start = f.exec_code.ptr()
        let end_ = start + f.code_size.to_int64()
        jit_module.address_ranges.push({ start, end: end_, func_idx })
      }
      jit_module.address_ranges.sort_by(fn(a, b) { a.start.compare(b.start) })
    }
  }
  jit_module
}

///|
/// Create a JITModule from a single compiled function (for testing)
/// This is a convenience method for unit tests that compile a single function
pub fn JITModule::from_single_function(
  code_bytes : Array[Int],
  func_name : String,
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
  mem_size : Int64,
) -> JITModule? {
  // Create context with 1 function slot
  let context = JITContext::new(1)
  match context {
    None => return None
    Some(ctx) => {
      // Allocate memory (guarded for memory32 bounds-check elimination)
      let pages = if mem_size <= 0L {
        0
      } else {
        ((mem_size + @types.WASM_PAGE_SIZE_BYTES - 1L) /
        @types.WASM_PAGE_SIZE_BYTES).to_int()
      }
      let actual_size = pages.to_int64() * @types.WASM_PAGE_SIZE_BYTES
      let mem_ptr = if pages > 0 {
        ctx.alloc_guarded_memory(pages, None)
      } else {
        0L
      }
      if mem_ptr == 0L && actual_size > 0L {
        return None
      }
      ctx.set_memory(mem_ptr)
      // Create executable code
      let exec_code = @wasmoon_jit.ExecCode::new(code_bytes)
      match exec_code {
        None => return None
        Some(ec) => {
          // Set function in table
          ctx.set_func(0, ec.ptr())
          // Create JIT function
          let jit_func = JITFunction::new(
            0,
            func_name,
            ec,
            code_bytes.length(),
            param_types,
            result_types,
          )
          // Create module
          let jit_module = JITModule::new()
          jit_module.functions.set(0, jit_func)
          jit_module.by_name.set(func_name, 0)
          let context_ptr = ctx.ptr()
          jit_module.context = Some(ctx)
          jit_module.context_ptr = context_ptr
          // Build address_ranges for this single function
          let start = ec.ptr()
          let end_ = start + code_bytes.length().to_int64()
          jit_module.address_ranges.push({ start, end: end_, func_idx: 0 })
          Some(jit_module)
        }
      }
    }
  }
}

///|
/// Get the raw VMContext pointer for this JIT module
/// Returns 0 if no context is available
pub fn JITModule::get_context_ptr(self : JITModule) -> Int64 {
  self.context_ptr
}

///|
/// Get the function table pointer for GC subtyping checks
/// Returns 0 if no context is available
pub fn JITModule::get_func_table_ptr(self : JITModule) -> Int64 {
  if self.context_ptr != 0L {
    @wasmoon_jit.context_func_table_ptr(self.context_ptr)
  } else {
    0L
  }
}

///|
/// Get the number of functions in the function table
/// Returns 0 if no context is available
pub fn JITModule::get_func_count(self : JITModule) -> Int {
  if self.context_ptr != 0L {
    @wasmoon_jit.context_func_count(self.context_ptr)
  } else {
    0
  }
}

///|
/// Get current table base pointer from active JIT context.
pub fn JITModule::get_table_ptr(self : JITModule, table_idx : Int) -> Int64 {
  if self.context_ptr != 0L {
    @wasmoon_jit.context_table_ptr(self.context_ptr, table_idx)
  } else {
    0L
  }
}

///|
/// Get current table size from active JIT context.
pub fn JITModule::get_table_size(self : JITModule, table_idx : Int) -> Int {
  if self.context_ptr != 0L {
    @wasmoon_jit.context_table_size(self.context_ptr, table_idx)
  } else {
    0
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
  match self.functions.get(func_idx) {
    Some(f) => f.exec_code.ptr()
    None => {
      let func_table_ptr = self.get_func_table_ptr()
      let func_count = self.get_func_count()
      if func_table_ptr != 0L && func_idx >= 0 && func_idx < func_count {
        @wasmoon_jit.c_jit_read_i64(func_table_ptr + func_idx.to_int64() * 8L)
      } else {
        0L
      }
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
    Some(f) => f.exec_code.ptr()
    None => 0L
  }
}

///|
/// Export all function pointers as a map from name to function pointer
/// Used for cross-module imports
pub fn JITModule::export_functions(self : JITModule) -> Map[String, Int64] {
  let exports : Map[String, Int64] = {}
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
        func.exec_code.ptr(),
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
        None => ()
      }
      results
    }
    None => [] // No context, cannot call
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
  if self.context_ptr != 0L {
    @wasmoon_jit.gc_set_context_heap_ptr(self.context_ptr, heap_ptr)
  }
}

///|
/// Push a GC frame node in current JIT context.
pub fn JITModule::gc_begin_frame(self : JITModule, frame_id : Int64) -> Unit {
  if self.context_ptr != 0L {
    @wasmoon_jit.gc_begin_frame(self.context_ptr, frame_id)
  }
}

///|
/// Pop a GC frame node in current JIT context.
pub fn JITModule::gc_end_frame(self : JITModule) -> Unit {
  if self.context_ptr != 0L {
    @wasmoon_jit.gc_end_frame(self.context_ptr)
  }
}

///|
/// Set context-local scratch roots for allocation retry collections.
pub fn JITModule::gc_set_root_scratch(
  self : JITModule,
  roots : Array[Int64],
) -> Bool {
  if self.context_ptr == 0L {
    return false
  }
  @wasmoon_jit.gc_set_root_scratch(self.context_ptr, roots)
}

///|
/// Set safepoint metadata table pointer for current context.
pub fn JITModule::gc_set_safepoint_table(
  self : JITModule,
  table_ptr : Int64,
) -> Unit {
  if self.context_ptr != 0L {
    @wasmoon_jit.gc_set_safepoint_table(self.context_ptr, table_ptr)
  }
}

///|
/// Install a function's GC safepoint table into context-owned storage.
pub fn JITModule::gc_set_func_safepoints(
  self : JITModule,
  func_idx : Int,
  safepoints : Array[@cwasm.GcSafepoint],
  stackmap_blob : Bytes,
) -> Bool {
  if self.context_ptr == 0L {
    return false
  }
  @wasmoon_jit.gc_set_func_safepoints(
    self.context_ptr,
    func_idx,
    safepoints,
    stackmap_blob,
  )
}

///|
/// Select currently active function safepoint table (`func_idx < 0` clears).
pub fn JITModule::gc_use_func_safepoints(
  self : JITModule,
  func_idx : Int,
) -> Unit {
  if self.context_ptr != 0L {
    @wasmoon_jit.gc_use_func_safepoints(self.context_ptr, func_idx)
  }
}

///|
/// Throw a payload-less wasm exception into the active JIT exception chain.
/// Used by hostcall bridges that need to surface imported-callee throws.
pub fn throw_exception_tag(ctx_ptr : Int64, tag_addr : Int) -> Unit {
  @wasmoon_jit.throw_exception_tag(ctx_ptr, tag_addr)
}

///|
/// Throw a wasm exception with payload values into the active JIT exception
/// chain (used by hostcall bridges).
pub fn throw_exception_values(
  ctx_ptr : Int64,
  tag_addr : Int,
  values : Array[Int64],
) -> Unit {
  @wasmoon_jit.throw_exception_values(ctx_ptr, tag_addr, values)
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
/// Allocate an independent WASM stack with guard page protection.
/// When enabled, JIT-compiled WASM code runs on a separate stack,
/// providing controlled stack overflow behavior:
/// - Stack overflows hit a guard page and trigger "call stack exhausted" trap
/// - Host stack is protected from runaway WASM recursion
/// - Cross-platform consistent behavior
///
/// Parameters:
///   stack_size: Size of the stack in bytes (default: 1MB = 1048576)
///
/// Returns: true on success, false on failure
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
/// Check if a WASM stack has been allocated
pub fn JITModule::has_wasm_stack(self : JITModule) -> Bool {
  match self.context {
    Some(ctx) => ctx.has_wasm_stack()
    None => false
  }
}

///|
/// Set the hostcall callback used for JIT -> host bridging.
/// The callback should return 0 on success, or a trap code on failure.
pub fn JITModule::set_hostcall_callback(
  self : JITModule,
  callback : () -> Int,
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
  @wasmoon_jit.setup_segments(
    ctx.ptr(),
    datas,
    elem_segments,
    data_dropped~,
    elem_dropped~,
  )
}

///|
/// Clear per-context segment state (frees owned segment buffers).
pub fn JITModule::clear_segments(self : JITModule) -> Unit {
  if self.context_ptr != 0L {
    @wasmoon_jit.clear_segments(self.context_ptr)
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
      None => @types.NULL_REF
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
  let dwarf = @wasmoon_jit.DWARFBuilder::new()
  for func_idx, func in self.functions {
    let addr = self.get_func_ptr(func_idx)
    dwarf.add_function(func.name, addr, func.code_size, func_idx)
  }
  dwarf.register(verbose~)
  dwarf
}
