///|
/// JIT Execution Runtime
/// Loads and executes precompiled .cwasm files

///|
/// JIT-compiled function ready for execution
pub struct JITFunction {
  func_idx : Int
  name : String
  priv exec_code : ExecCode
  priv code_size : Int
  param_types : Array[@types.ValueType] // Parameter types for proper register allocation
  result_types : Array[@types.ValueType] // Return types (empty = void, 1 = single, 2+ = multi-value)
}

///|
/// Per-function compilation dumps captured for dump-on-trap.
pub struct JITFunctionDebug {
  ir : String
  vcode_before_regalloc : String
  vcode_after_regalloc : String
  machine_code : String
}

///|
pub fn JITFunctionDebug::new(
  ir : String,
  vcode_before_regalloc : String,
  vcode_after_regalloc : String,
  machine_code : String,
) -> JITFunctionDebug {
  { ir, vcode_before_regalloc, vcode_after_regalloc, machine_code }
}

///|
/// Optional in-memory database of per-function debug dumps.
pub struct JITDebugDB {
  entries : Map[Int, JITFunctionDebug]
}

///|
pub fn JITDebugDB::new() -> JITDebugDB {
  { entries: Map::new() }
}

///|
pub fn JITDebugDB::set(
  self : JITDebugDB,
  func_idx : Int,
  debug : JITFunctionDebug,
) -> Unit {
  self.entries.set(func_idx, debug)
}

///|
pub fn JITDebugDB::get(self : JITDebugDB, func_idx : Int) -> JITFunctionDebug? {
  self.entries.get(func_idx)
}

///|
fn JITFunction::new(
  func_idx : Int,
  name : String,
  exec_code : ExecCode,
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
} derive(Show)

///|
/// Loaded precompiled module with executable functions
struct JITModule {
  functions : Map[Int, JITFunction]
  by_name : Map[String, Int]
  address_ranges : Array[AddressRange] // Sorted by start address for binary search
  mut context : JITContext?
  mut debug_db : JITDebugDB?
  mut wasi_stdout_callback : ((Bytes) -> Unit)?
  mut wasi_stderr_callback : ((Bytes) -> Unit)?
}

///|
pub fn JITModule::new() -> JITModule {
  {
    functions: Map::new(),
    by_name: Map::new(),
    address_ranges: [],
    context: None,
    debug_db: None,
    wasi_stdout_callback: None,
    wasi_stderr_callback: None,
  }
}

///|
fn pack_u64_le(bytes : Array[Int], start : Int) -> Int64 {
  let mut value : Int64 = 0L
  for i in 0..<8 {
    let b = bytes[start + i].to_int64() & 0xFFL
    value = value | (b << (i * 8))
  }
  value
}

///|
fn emit_load_imm64_fixed_bytes(reg : Int, imm : Int64) -> Array[Int] {
  let mc = @emit.MachineCode::new()
  mc.emit_load_imm64_fixed(reg, imm)
  mc.get_bytes()
}

///|
fn patch_load_imm64_fixed(
  exec_ptr : Int64,
  fixup : @emit.FuncAddrFixup,
  func_ptr : Int64,
) -> Unit {
  let bytes = emit_load_imm64_fixed_bytes(fixup.reg, func_ptr)
  if bytes.length() != 16 {
    abort("unexpected load_imm64_fixed size")
  }
  let base = exec_ptr + fixup.offset.to_int64()
  c_jit_write_i64(base, pack_u64_le(bytes, 0))
  c_jit_write_i64(base + 8L, pack_u64_le(bytes, 8))
}

///|
fn apply_func_addr_fixups(
  ctx : JITContext,
  jit_module : JITModule,
  precompiled : @cwasm.PrecompiledModule,
) -> Unit {
  let func_table_ptr = ctx.get_func_table_ptr()
  if func_table_ptr == 0L {
    return
  }
  for entry in precompiled.functions {
    if entry.func_addr_fixups.length() == 0 {
      continue
    }
    match jit_module.functions.get(entry.func_idx) {
      Some(func) => {
        let exec_ptr = func.exec_code.ptr()
        for fixup in entry.func_addr_fixups {
          let target_ptr = c_jit_read_i64(
            func_table_ptr + fixup.func_idx.to_int64() * 8L,
          )
          patch_load_imm64_fixed(exec_ptr, fixup, target_ptr)
        }
      }
      None => ()
    }
  }
}

///|
fn patch_direct_call(
  exec_ptr : Int64,
  fixup : @emit.CallFixup,
  target_ptr : Int64,
) -> Unit {
  let pc = exec_ptr + fixup.offset.to_int64()
  let diff = target_ptr - pc
  if diff % 4L != 0L {
    abort("direct call target misaligned")
  }
  let imm26 = diff / 4L
  if imm26 < -0x2000000L || imm26 > 0x1FFFFFFL {
    abort("direct call target out of range")
  }
  let encoded = (0x94000000L | (imm26 & 0x3FFFFFFL)).to_int()
  c_jit_write_u32(pc, encoded)
}

///|
fn apply_call_fixups(
  ctx : JITContext,
  jit_module : JITModule,
  precompiled : @cwasm.PrecompiledModule,
) -> Unit {
  let func_table_ptr = ctx.get_func_table_ptr()
  if func_table_ptr == 0L {
    return
  }
  for entry in precompiled.functions {
    if entry.call_fixups.length() == 0 {
      continue
    }
    match jit_module.functions.get(entry.func_idx) {
      Some(func) => {
        let exec_ptr = func.exec_code.ptr()
        for fixup in entry.call_fixups {
          let target_ptr = c_jit_read_i64(
            func_table_ptr + fixup.func_idx.to_int64() * 8L,
          )
          patch_direct_call(exec_ptr, fixup, target_ptr)
        }
      }
      None => ()
    }
  }
}

///|
/// Load a precompiled module
/// func_signatures: Array of (param_types, result_types) for each func_idx
pub fn JITModule::load(
  precompiled : @cwasm.PrecompiledModule,
  func_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])],
  debug_db? : JITDebugDB? = None,
) -> JITModule? {
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
  debug_db? : JITDebugDB? = None,
) -> JITModule? {
  let jit_module = JITModule::new()
  let num_imports = precompiled.imports.length()

  // Calculate total function count: imports + compiled functions
  let total_funcs = num_imports + precompiled.functions.length()

  // Create JIT context with function table
  let context = JITContext::new(total_funcs)
  match context {
    None => return None
    Some(ctx) => {
      // Step 1: Populate import trampolines into function table
      for i, imp in precompiled.imports {
        // First check external imports, then fall back to built-in trampolines
        let func_ptr : Int64? = match external_imports.get(imp.module_name) {
          Some(m) => m.get(imp.func_name)
          None => None
        }
        let func_ptr : Int64? = match func_ptr {
          Some(_) => func_ptr
          None => get_import_trampoline(imp.module_name, imp.func_name)
        }
        match func_ptr {
          Some(ptr) => ctx.set_func(i, ptr)
          None => return None // Unsupported import
        }
      }

      // Step 2: Load compiled functions and populate their pointers
      for entry in precompiled.functions {
        // Allocate executable memory directly from code array
        let exec_code = ExecCode::new(entry.code)
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
          }
          None => return None
        }
      }

      // Store context in module
      jit_module.context = Some(ctx)
      jit_module.debug_db = debug_db

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
  Some(jit_module)
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
        ((mem_size + 65535L) / 65536L).to_int()
      }
      let actual_size = pages.to_int64() * 65536L
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
      let exec_code = ExecCode::new(code_bytes)
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
          jit_module.context = Some(ctx)
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
/// Get the function table pointer for GC subtyping checks
/// Returns 0 if no context is available
pub fn JITModule::get_func_table_ptr(self : JITModule) -> Int64 {
  match self.context {
    Some(ctx) => ctx.get_func_table_ptr()
    None => 0L
  }
}

///|
/// Get the number of functions in the function table
/// Returns 0 if no context is available
pub fn JITModule::get_func_count(self : JITModule) -> Int {
  match self.context {
    Some(ctx) => ctx.get_func_count()
    None => 0
  }
}

///|
/// Trampoline registry - maps (module, field) to function pointer getter
let import_trampolines : Map[String, Map[String, () -> Int64]] = {
  let m : Map[String, Map[String, () -> Int64]] = {}
  // WASI functions - full WASI Preview1 support
  m["wasi_snapshot_preview1"] = {
    // File descriptor operations
    "fd_write": get_fd_write_ptr,
    "fd_read": get_fd_read_ptr,
    "fd_close": get_fd_close_ptr,
    "fd_seek": get_fd_seek_ptr,
    "fd_tell": get_fd_tell_ptr,
    "fd_sync": get_fd_sync_ptr,
    "fd_datasync": get_fd_datasync_ptr,
    "fd_fdstat_get": get_fd_fdstat_get_ptr,
    "fd_fdstat_set_flags": get_fd_fdstat_set_flags_ptr,
    "fd_fdstat_set_rights": get_fd_fdstat_set_rights_ptr,
    "fd_prestat_get": get_fd_prestat_get_ptr,
    "fd_prestat_dir_name": get_fd_prestat_dir_name_ptr,
    "fd_filestat_get": get_fd_filestat_get_ptr,
    "fd_filestat_set_size": get_fd_filestat_set_size_ptr,
    "fd_filestat_set_times": get_fd_filestat_set_times_ptr,
    "fd_advise": get_fd_advise_ptr,
    "fd_allocate": get_fd_allocate_ptr,
    "fd_pread": get_fd_pread_ptr,
    "fd_pwrite": get_fd_pwrite_ptr,
    "fd_readdir": get_fd_readdir_ptr,
    "fd_renumber": get_fd_renumber_ptr,
    // Path operations
    "path_open": get_path_open_ptr,
    "path_create_directory": get_path_create_directory_ptr,
    "path_unlink_file": get_path_unlink_file_ptr,
    "path_remove_directory": get_path_remove_directory_ptr,
    "path_rename": get_path_rename_ptr,
    "path_filestat_get": get_path_filestat_get_ptr,
    "path_filestat_set_times": get_path_filestat_set_times_ptr,
    "path_link": get_path_link_ptr,
    "path_readlink": get_path_readlink_ptr,
    "path_symlink": get_path_symlink_ptr,
    // Environment and arguments
    "args_sizes_get": get_args_sizes_get_ptr,
    "args_get": get_args_get_ptr,
    "environ_sizes_get": get_environ_sizes_get_ptr,
    "environ_get": get_environ_get_ptr,
    // Clock and random
    "clock_time_get": get_clock_time_get_ptr,
    "clock_res_get": get_clock_res_get_ptr,
    "random_get": get_random_get_ptr,
    // Process
    "proc_exit": get_proc_exit_ptr,
    "proc_raise": get_proc_raise_ptr,
    "sched_yield": get_sched_yield_ptr,
    // Poll
    "poll_oneoff": get_poll_oneoff_ptr,
    // Socket (stubs - return ENOTSUP)
    "sock_accept": get_sock_accept_ptr,
    "sock_recv": get_sock_recv_ptr,
    "sock_send": get_sock_send_ptr,
    "sock_shutdown": get_sock_shutdown_ptr,
  }
  // Spectest functions
  m["spectest"] = {
    "print": get_spectest_print_ptr,
    "print_i32": get_spectest_print_i32_ptr,
    "print_i64": get_spectest_print_i64_ptr,
    "print_f32": get_spectest_print_f32_ptr,
    "print_f64": get_spectest_print_f64_ptr,
    "print_i32_f32": get_spectest_print_i32_f32_ptr,
    "print_f64_f64": get_spectest_print_f64_f64_ptr,
    "print_char": get_spectest_print_char_ptr,
  }
  m
}

///|
/// Get trampoline function pointer for an import
/// Returns None if the import is not supported by JIT
pub fn get_import_trampoline(
  module_name : String,
  field_name : String,
) -> Int64? {
  import_trampolines
  .get(module_name)
  .bind(fn(m) { m.get(field_name) })
  .map(fn(f) { f() })
}

///|
/// Check if a module is known to JIT (has trampoline support)
/// JIT can handle imports from these modules without interpreter state sharing
pub fn is_jit_supported_module(module_name : String) -> Bool {
  import_trampolines.contains(module_name)
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
    None => 0L
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
      // Calculate number of result slots (V128 needs 2 slots, others need 1)
      let mut num_result_slots = 0
      for result_type in func.result_types {
        if result_type is @types.ValueType::V128 {
          num_result_slots = num_result_slots + 2
        } else {
          num_result_slots = num_result_slots + 1
        }
      }
      let results : Array[Int64] = Array::make(num_result_slots, 0L)
      let mut call_error : JITTrap? = None
      ctx.call_multi_return(
        func.exec_code.ptr(),
        args,
        func.param_types,
        results,
        func.result_types,
      ) catch {
        e => call_error = Some(e)
      }
      self.flush_wasi_output(ctx)
      match call_error {
        Some(JITTrap(msg)) => raise JITTrap(self.enrich_trap_message(msg))
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
fn JITModule::enrich_trap_message(self : JITModule, msg : String) -> String {
  let details = get_last_trap_details()
  let fields : Array[String] = []
  if details.signal != 0 {
    fields.push("sig=\{format_signal(details.signal)}")
  }
  if details.pc != 0L {
    fields.push("pc=\{to_hex_u64(details.pc)}")
  }
  if details.lr != 0L {
    fields.push("lr=\{to_hex_u64(details.lr)}")
  }
  if details.frame_lr != 0L {
    fields.push("frame_lr=\{to_hex_u64(details.frame_lr)}")
  }
  if details.fault_addr != 0L {
    fields.push("addr=\{to_hex_u64(details.fault_addr)}")
  }
  if details.brk_imm >= 0 {
    fields.push("brk_imm=\{details.brk_imm}")
  }

  // Prefer PC-range mapping; fall back to current-func tracking.
  let mut resolved_func_idx : Int? = None
  let mut func_desc : String? = None
  match self.find_func_by_pc(details.pc) {
    Some((func_idx, f, offset)) => {
      resolved_func_idx = Some(func_idx)
      func_desc = Some(
        "wasm=\{func_idx} '\{f.name}'+0x\{@types.int_to_hex(offset)}",
      )
    }
    None =>
      if details.func_idx >= 0 {
        resolved_func_idx = Some(details.func_idx)
        match self.functions.get(details.func_idx) {
          Some(f) => func_desc = Some("wasm=\{details.func_idx} '\{f.name}'")
          None => func_desc = Some("wasm=\{details.func_idx}")
        }
      }
  }
  match func_desc {
    Some(s) => fields.push(s)
    None => ()
  }

  // Best-effort caller mapping via the saved LR in the frame record.
  let mut caller : (Int, JITFunction, Int, Int64)? = None
  if details.frame_lr != 0L {
    match self.find_func_by_pc(details.frame_lr) {
      Some((func_idx, f, offset)) =>
        caller = Some((func_idx, f, offset, details.frame_lr))
      None =>
        if details.frame_lr >= 4L {
          let lr_prev = details.frame_lr - 4L
          match self.find_func_by_pc(lr_prev) {
            Some((func_idx, f, offset)) =>
              caller = Some((func_idx, f, offset, lr_prev))
            None => ()
          }
        }
    }
  }
  match caller {
    Some((func_idx, f, offset, _)) =>
      fields.push(
        "caller=\{func_idx} '\{f.name}'+0x\{@types.int_to_hex(offset)}",
      )
    None => ()
  }

  // Dump-on-trap (optional): write a single per-trap file for the resolved function.
  match (resolved_func_idx, self.debug_db) {
    (Some(func_idx), Some(db)) =>
      match db.get(func_idx) {
        Some(dbg) => {
          let name = match self.functions.get(func_idx) {
            Some(f) => f.name
            None => "func\{func_idx}"
          }
          let path = "target/jit-trap-\{func_idx}-\{sanitize_filename(name)}.log"
          let content = "func_idx: \{func_idx}\n" +
            "name: \{name}\n" +
            "signal: \{details.signal}\n" +
            "pc: \{to_hex_u64(details.pc)}\n" +
            "lr: \{to_hex_u64(details.lr)}\n" +
            "frame_lr: \{to_hex_u64(details.frame_lr)}\n" +
            "fault_addr: \{to_hex_u64(details.fault_addr)}\n" +
            "brk_imm: \{details.brk_imm}\n\n" +
            "== IR ==\n" +
            dbg.ir +
            "\n\n" +
            "== VCode (before regalloc) ==\n" +
            dbg.vcode_before_regalloc +
            "\n\n" +
            "== VCode (after regalloc) ==\n" +
            dbg.vcode_after_regalloc +
            "\n\n" +
            "== Machine Code ==\n" +
            dbg.machine_code +
            "\n"
          let content = match caller {
            Some((caller_idx, caller_func, _caller_off, caller_pc)) =>
              match db.get(caller_idx) {
                Some(cdbg) =>
                  content +
                  "\n== Caller ==\n" +
                  "caller_func_idx: \{caller_idx}\n" +
                  "caller_name: \{caller_func.name}\n" +
                  "caller_pc: \{to_hex_u64(caller_pc)}\n\n" +
                  "== Caller IR ==\n" +
                  cdbg.ir +
                  "\n\n" +
                  "== Caller VCode (before regalloc) ==\n" +
                  cdbg.vcode_before_regalloc +
                  "\n\n" +
                  "== Caller VCode (after regalloc) ==\n" +
                  cdbg.vcode_after_regalloc +
                  "\n\n" +
                  "== Caller Machine Code ==\n" +
                  cdbg.machine_code +
                  "\n"
                None => content
              }
            None => content
          }
          @fs.write_string_to_file(path, content) catch {
            _ => ()
          }
          fields.push("dump=\{path}")
        }
        None => ()
      }
    _ => ()
  }
  if fields.is_empty() {
    msg
  } else {
    msg + " (" + fields.join(", ") + ")"
  }
}

///|
fn format_signal(sig : Int) -> String {
  match sig {
    5 => "SIGTRAP(5)"
    10 => "SIGBUS(10)"
    11 => "SIGSEGV(11)"
    7 => "SIGBUS(7)"
    _ => "SIG(\{sig})"
  }
}

///|
fn to_hex_u64(v : Int64) -> String {
  let u = v.reinterpret_as_uint64()
  let b7 = (u >> 56).reinterpret_as_int64().to_int() & 0xFF
  let b6 = (u >> 48).reinterpret_as_int64().to_int() & 0xFF
  let b5 = (u >> 40).reinterpret_as_int64().to_int() & 0xFF
  let b4 = (u >> 32).reinterpret_as_int64().to_int() & 0xFF
  let b3 = (u >> 24).reinterpret_as_int64().to_int() & 0xFF
  let b2 = (u >> 16).reinterpret_as_int64().to_int() & 0xFF
  let b1 = (u >> 8).reinterpret_as_int64().to_int() & 0xFF
  let b0 = u.reinterpret_as_int64().to_int() & 0xFF
  "0x" +
  @types.to_hex_byte(b7) +
  @types.to_hex_byte(b6) +
  @types.to_hex_byte(b5) +
  @types.to_hex_byte(b4) +
  @types.to_hex_byte(b3) +
  @types.to_hex_byte(b2) +
  @types.to_hex_byte(b1) +
  @types.to_hex_byte(b0)
}

///|
fn sanitize_filename(s : String) -> String {
  let mut out = ""
  for c in s {
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-' ||
      c == '.'
    out = out + (if ok { c.to_string() } else { "_" })
  }
  if out.is_empty() {
    "unknown"
  } else {
    out
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
  if self.context is Some(ctx) {
    ctx.set_gc_heap(heap_ptr)
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
  memories : Array[MemoryInfo],
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
/// Set up data segments before JIT execution.
/// This must be called before running code that uses memory.init or data.drop.
/// The segments are stored globally and accessed by libcalls.
pub fn setup_data_segments(datas : Array[@types.Data]) -> Unit {
  if datas.is_empty() {
    return
  }
  let count = datas.length()
  // Initialize storage for all segments
  @jit_ffi.c_jit_init_data_segments(count)
  // Add each segment one by one - C copies immediately during each call
  for i, data in datas {
    let bytes = data.init
    let size = bytes.length()
    if size > 0 {
      // Create FixedArray and copy bytes
      let buf = FixedArray::make(size, b'\x00')
      for j in 0..<size {
        buf[j] = bytes[j]
      }
      // C copies immediately during this call, so buf can be GC'd after
      @jit_ffi.c_jit_add_data_segment(i, buf, size)
    }
    // Empty segments are handled by init (initialized to NULL)
  }
}

///|
/// Set up element segments before JIT execution.
/// This must be called before running code that uses table.init or elem.drop.
/// The segments are stored globally and accessed by libcalls.
/// elem_values: Array of Int64 arrays, one per element segment
///   Each Int64 represents an encoded funcref table entry (tagged func ptr) or null (0)
pub fn setup_elem_segments(elem_values : Array[Array[Int64]]) -> Unit {
  if elem_values.is_empty() {
    return
  }
  let count = elem_values.length()
  // Initialize storage for all segments
  @jit_ffi.c_jit_init_elem_segments(count)
  // Add each segment one by one - C copies immediately during each call
  for i, values in elem_values {
    let size = values.length()
    if size > 0 {
      // Create FixedArray and copy values
      let buf = FixedArray::make(size, 0L)
      for j in 0..<size {
        buf[j] = values[j]
      }
      // C copies immediately during this call, so buf can be GC'd after
      @jit_ffi.c_jit_add_elem_segment(i, buf, size)
    }
    // Empty segments are handled by init (initialized to NULL)
  }
}

///|
/// Clear segment state after JIT execution.
/// Call this after JIT execution completes to release global segment storage.
pub fn clear_segments() -> Unit {
  @jit_ffi.c_jit_clear_segments()
}

///|
/// Initialize shared tables from Store (for multi-table support with table imports/exports).
/// jit_tables: Array of JITTable from Store (one per runtime table)
/// elem_init: Array of (table_idx, elem_idx, func_idx?, type_hash) tuples
pub fn JITModule::init_shared_tables(
  self : JITModule,
  jit_tables : Array[JITTable?],
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
      Some(idx) => tag_funcref_ptr(self.get_func_ptr(idx))
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
) -> DWARFBuilder {
  let dwarf = DWARFBuilder::new()
  for func_idx, func in self.functions {
    let addr = self.get_func_ptr(func_idx)
    dwarf.add_function(func.name, addr, func.code_size, func_idx)
  }
  dwarf.register(verbose~)
  dwarf
}
