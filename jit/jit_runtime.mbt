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
/// Free the JIT function's executable memory
fn JITFunction::free(self : JITFunction) -> Unit {
  self.exec_code.free()
}

///|
/// Loaded precompiled module with executable functions
pub struct JITModule {
  priv functions : Map[Int, JITFunction]
  priv by_name : Map[String, Int]
  priv mut context : JITContext?
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
        let func_ptr = get_import_trampoline(imp.module_name, imp.func_name)
        ctx.set_func(i, func_ptr)
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
            ctx.set_func(entry.func_idx, ec.ptr)
          }
          None => {
            // Failed to allocate, clean up
            for kv in jit_module.functions.iter() {
              kv.1.free()
            }
            ctx.free()
            return None
          }
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
        ctx.free()
        return None
      }
      ctx.set_memory(mem_ptr, mem_size)
      // Create executable code
      let exec_code = ExecCode::new(code_bytes)
      match exec_code {
        None => {
          free_memory(mem_ptr)
          ctx.free()
          return None
        }
        Some(ec) => {
          // Set function in table
          ctx.set_func(0, ec.ptr)
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
/// Get trampoline function pointer for a WASI import
fn get_import_trampoline(module_name : String, field_name : String) -> Int64 {
  if module_name == "wasi_snapshot_preview1" {
    match field_name {
      "fd_write" => get_fd_write_ptr()
      "fd_read" => get_fd_read_ptr()
      "fd_close" => get_fd_close_ptr()
      "fd_fdstat_get" => get_fd_fdstat_get_ptr()
      "fd_prestat_get" => get_fd_prestat_get_ptr()
      "proc_exit" => get_proc_exit_ptr()
      "args_sizes_get" => get_args_sizes_get_ptr()
      "args_get" => get_args_get_ptr()
      "environ_sizes_get" => get_environ_sizes_get_ptr()
      "environ_get" => get_environ_get_ptr()
      "clock_time_get" => get_clock_time_get_ptr()
      "random_get" => get_random_get_ptr()
      _ => 0L // Unknown WASI function
    }
  } else if module_name == "spectest" {
    match field_name {
      "print" => get_spectest_print_ptr()
      "print_i32" => get_spectest_print_i32_ptr()
      "print_i64" => get_spectest_print_i64_ptr()
      "print_f32" => get_spectest_print_f32_ptr()
      "print_f64" => get_spectest_print_f64_ptr()
      "print_i32_f32" => get_spectest_print_i32_f32_ptr()
      "print_f64_f64" => get_spectest_print_f64_f64_ptr()
      _ => 0L // Unknown spectest function
    }
  } else {
    0L // Unknown module
  }
}

///|
/// Check if an import has a JIT trampoline implementation
pub fn has_import_trampoline(module_name : String, field_name : String) -> Bool {
  get_import_trampoline(module_name, field_name) != 0L
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
/// Free all executable memory
pub fn JITModule::free(self : JITModule) -> Unit {
  for kv in self.functions.iter() {
    kv.1.free()
  }
  match self.context {
    Some(ctx) => ctx.free()
    None => ()
  }
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
      // Activate context for WASI calls
      ctx.activate()
      let num_results = func.result_types.length()
      let results : Array[Int64] = Array::make(num_results, 0L)
      ctx.call_multi_return(
        func.exec_code.ptr,
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
  match self.context {
    Some(ctx) => ctx.set_memory(mem_ptr, mem_size)
    None => ()
  }
}

///|
/// Initialize indirect table for call_indirect.
/// table_size: number of table elements
/// elem_init: array of (table_idx, func_idx) pairs
pub fn JITModule::init_indirect_table(
  self : JITModule,
  table_size : Int,
  elem_init : Array[(Int, Int)],
) -> Unit {
  match self.context {
    Some(ctx) =>
      if ctx.alloc_indirect_table(table_size) {
        for entry in elem_init {
          let (table_idx, func_idx) = entry
          ctx.set_indirect(table_idx, func_idx)
        }
      }
    None => ()
  }
}
