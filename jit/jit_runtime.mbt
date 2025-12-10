///|
/// JIT Execution Runtime
/// Loads and executes precompiled .cwasm files

///|
/// Return type for JIT functions
pub(all) enum JITReturnType {
  None // No return value
  Int // Integer return (i32, i64) - uses X0
  Float // Float return (f32, f64) - uses D0, internally always f64
} derive(Eq, Show)

///|
/// JIT-compiled function ready for execution
pub(all) struct JITFunction {
  name : String
  func_idx : Int
  exec_code : ExecCode
  frame_size : Int
  num_params : Int
  has_result : Bool // Keep for backwards compatibility
  result_type : JITReturnType // Actual return type info
}

///|
pub fn JITFunction::new(
  name : String,
  func_idx : Int,
  exec_code : ExecCode,
  frame_size : Int,
  num_params : Int,
  has_result : Bool,
  result_type : JITReturnType,
) -> JITFunction {
  { name, func_idx, exec_code, frame_size, num_params, has_result, result_type }
}

///|
/// Call the function with i64 arguments
pub fn JITFunction::call(self : JITFunction, args : Array[Int64]) -> Int64? {
  // Validate argument count
  if args.length() != self.num_params {
    return None
  }
  // Call based on number of arguments and return type
  if self.has_result {
    let result = match self.num_params {
      0 => self.exec_code.call_void_i64()
      1 => self.exec_code.call_i64_i64(args[0])
      2 => self.exec_code.call_i64i64_i64(args[0], args[1])
      3 => self.exec_code.call_i64i64i64_i64(args[0], args[1], args[2])
      4 =>
        self.exec_code.call_i64i64i64i64_i64(args[0], args[1], args[2], args[3])
      _ => return None // Too many arguments
    }
    Some(result)
  } else {
    match self.num_params {
      0 => self.exec_code.call_void_void()
      1 => self.exec_code.call_i64_void(args[0])
      2 => self.exec_code.call_i64i64_void(args[0], args[1])
      3 => self.exec_code.call_i64i64i64_void(args[0], args[1], args[2])
      4 =>
        self.exec_code.call_i64i64i64i64_void(
          args[0],
          args[1],
          args[2],
          args[3],
        )
      _ => return None
    }
    None
  }
}

///|
/// Free the JIT function's executable memory
pub fn JITFunction::free(self : JITFunction) -> Unit {
  self.exec_code.free()
}

///|
/// Debug print the machine code
pub fn JITFunction::debug_print(self : JITFunction) -> Unit {
  println("JIT Function: \{self.name} (idx=\{self.func_idx})")
  println("  Params: \{self.num_params}, Returns: \{self.has_result}")
  println("  Frame size: \{self.frame_size}")
  self.exec_code.debug_print()
}

///|
/// Loaded precompiled module with executable functions
pub(all) struct JITModule {
  functions : Map[Int, JITFunction]
  by_name : Map[String, Int]
  mut context : JITContext?
  mut num_imports : Int
}

///|
pub fn JITModule::new() -> JITModule {
  { functions: Map::new(), by_name: Map::new(), context: None, num_imports: 0 }
}

///|
/// Load a precompiled module
/// func_types: Array of (num_params, has_result) for each func_idx (for backwards compat)
/// result_types: Array of JITReturnType for each func_idx (for float support), can be empty
pub fn JITModule::load(
  precompiled : @cwasm.PrecompiledModule,
  func_types : Array[(Int, Bool)],
  result_types : Array[JITReturnType],
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
            let (num_params, has_result) = func_types
              .iter()
              .nth(entry.func_idx)
              .unwrap_or((0, false))
            // Get result type if provided
            let result_type = if entry.func_idx < result_types.length() {
              result_types[entry.func_idx]
            } else if has_result {
              JITReturnType::Int // Default to Int for backwards compatibility
            } else {
              JITReturnType::None
            }
            let jit_func = JITFunction::new(
              entry.name,
              entry.func_idx,
              ec,
              entry.frame_size,
              num_params,
              has_result,
              result_type,
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
      jit_module.num_imports = num_imports
    }
  }
  Some(jit_module)
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
/// Returns Int64 for both int and float results:
/// - For Int return type: the value is directly in Int64
/// - For Float return type: the value is the bits of a f64 (Double) reinterpreted as Int64
pub fn JITModule::call_with_context(
  self : JITModule,
  func : JITFunction,
  args : Array[Int64],
) -> Int64? raise JITTrap {
  match self.context {
    Some(ctx) => {
      // Activate context for WASI calls
      ctx.activate()
      // Call using appropriate method based on return type
      match func.result_type {
        // Float returns - use f64 call (result is bits of double in Int64)
        JITReturnType::Float => {
          let result : Double = match args.length() {
            0 => ctx.call_void_f64(func.exec_code.ptr)
            1 => ctx.call_i64_f64(func.exec_code.ptr, args[0])
            2 => ctx.call_i64i64_f64(func.exec_code.ptr, args[0], args[1])
            _ => return None // Too many arguments
          }
          Some(result.reinterpret_as_int64())
        }
        // Integer returns - use i64 call
        JITReturnType::Int => {
          let result = match args.length() {
            0 => ctx.call_void_i64(func.exec_code.ptr)
            1 => ctx.call_i64_i64(func.exec_code.ptr, args[0])
            2 => ctx.call_i64i64_i64(func.exec_code.ptr, args[0], args[1])
            _ => return None // Too many arguments
          }
          Some(result)
        }
        // No return - use void call
        JITReturnType::None => {
          match args.length() {
            0 => ctx.call_void_void(func.exec_code.ptr)
            1 => ctx.call_i64_void(func.exec_code.ptr, args[0])
            2 => ctx.call_i64i64_void(func.exec_code.ptr, args[0], args[1])
            _ => return None // Too many arguments
          }
          None
        }
      }
    }
    None =>
      // Fallback to direct call (no context)
      func.call(args)
  }
}
