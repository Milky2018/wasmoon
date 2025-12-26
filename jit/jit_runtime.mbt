///|
/// JIT Execution Runtime
/// Loads and executes precompiled .cwasm files

///|
/// JIT-compiled function ready for execution
pub struct JITFunction {
  name : String
  priv exec_code : ExecCode
  param_types : Array[@types.ValueType] // Parameter types for proper register allocation
  result_types : Array[@types.ValueType] // Return types (empty = void, 1 = single, 2+ = multi-value)
}

///|
fn JITFunction::new(
  name : String,
  exec_code : ExecCode,
  param_types : Array[@types.ValueType],
  result_types : Array[@types.ValueType],
) -> JITFunction {
  { name, exec_code, param_types, result_types }
}

///|
/// Loaded precompiled module with executable functions
struct JITModule {
  functions : Map[Int, JITFunction]
  by_name : Map[String, Int]
  mut context : JITContext?
}

///|
pub fn JITModule::new() -> JITModule {
  { functions: Map::new(), by_name: Map::new(), context: None }
}

///|
/// Load a precompiled module
/// func_signatures: Array of (param_types, result_types) for each func_idx
pub fn JITModule::load(
  precompiled : @cwasm.PrecompiledModule,
  func_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])],
) -> JITModule? {
  JITModule::load_with_imports(precompiled, func_signatures, {})
}

///|
/// Load a precompiled module with external import resolution
/// func_signatures: Array of (param_types, result_types) for each func_idx
/// external_imports: Map from (module_name, func_name) to function pointer
pub fn JITModule::load_with_imports(
  precompiled : @cwasm.PrecompiledModule,
  func_signatures : Array[(Array[@types.ValueType], Array[@types.ValueType])],
  external_imports : Map[String, Map[String, Int64]],
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
              entry.name,
              ec,
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
      // Allocate memory
      let mem_ptr = alloc_memory(mem_size)
      if mem_ptr == 0L {
        return None
      }
      ctx.set_memory(mem_ptr, mem_size)
      // Create executable code
      let exec_code = ExecCode::new(code_bytes)
      match exec_code {
        None => return None
        Some(ec) => {
          // Set function in table
          ctx.set_func(0, ec.ptr())
          // Create JIT function
          let jit_func = JITFunction::new(
            func_name, ec, param_types, result_types,
          )
          // Create module
          let jit_module = JITModule::new()
          jit_module.functions.set(0, jit_func)
          jit_module.by_name.set(func_name, 0)
          jit_module.context = Some(ctx)
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
  // WASI functions
  m["wasi_snapshot_preview1"] = {
    "fd_write": get_fd_write_ptr,
    "fd_read": get_fd_read_ptr,
    "fd_close": get_fd_close_ptr,
    "fd_fdstat_get": get_fd_fdstat_get_ptr,
    "fd_prestat_get": get_fd_prestat_get_ptr,
    "proc_exit": get_proc_exit_ptr,
    "args_sizes_get": get_args_sizes_get_ptr,
    "args_get": get_args_get_ptr,
    "environ_sizes_get": get_environ_sizes_get_ptr,
    "environ_get": get_environ_get_ptr,
    "clock_time_get": get_clock_time_get_ptr,
    "random_get": get_random_get_ptr,
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
      let num_results = func.result_types.length()
      let results : Array[Int64] = Array::make(num_results, 0L)
      ctx.call_multi_return(
        func.exec_code.ptr(),
        args,
        func.param_types,
        results,
        func.result_types,
      )
      results
    }
    None => [] // No context, cannot call
  }
}

///|
/// Set memory for the JIT context
pub fn JITModule::set_memory(
  self : JITModule,
  mem_ptr : Int64,
  mem_size : Int64,
) -> Unit {
  if self.context is Some(ctx) {
    ctx.set_memory(mem_ptr, mem_size)
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

///|
/// Initialize shared tables from Store (for multi-table support with table imports/exports).
/// jit_tables: Array of JITTable from Store (one per runtime table)
/// elem_init: Array of (table_idx, elem_idx, func_idx, type_hash) tuples
pub fn JITModule::init_shared_tables(
  self : JITModule,
  jit_tables : Array[JITTable?],
  elem_init : Array[(Int, Int, Int, Int)],
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
    // Get function pointer and encode as funcref
    // func_idx = -1 represents ref.null (null reference sentinel)
    let funcref_value = if func_idx == -1 {
      0L // Use 0 for null reference (matches new encoding)
    } else {
      // Tag function pointer with FUNCREF_TAG (bit 61) for ref.test detection
      // FUNCREF_TAG = 0x2000000000000000
      self.get_func_ptr(func_idx) | 0x2000000000000000L
    }
    // Set the table entry (including null references)
    jit_table.set(elem_idx, funcref_value, type_hash)
  }
}
