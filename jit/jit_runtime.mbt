///|
/// JIT Execution Runtime
/// Loads and executes precompiled .cwasm files

///|
/// JIT-compiled function ready for execution
pub(all) struct JITFunction {
  name : String
  func_idx : Int
  exec_code : ExecCode
  frame_size : Int
  num_params : Int
  has_result : Bool
}

///|
pub fn JITFunction::new(
  name : String,
  func_idx : Int,
  exec_code : ExecCode,
  frame_size : Int,
  num_params : Int,
  has_result : Bool,
) -> JITFunction {
  { name, func_idx, exec_code, frame_size, num_params, has_result }
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
pub fn JITModule::load(
  precompiled : @cwasm.PrecompiledModule,
  func_types : Array[(Int, Bool)], // (num_params, has_result) for each func_idx
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
            let jit_func = JITFunction::new(
              entry.name,
              entry.func_idx,
              ec,
              entry.frame_size,
              num_params,
              has_result,
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
      "proc_exit" => get_proc_exit_ptr()
      _ => 0L // Unknown WASI function
    }
  } else {
    0L // Unknown module
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
pub fn JITModule::call_with_context(
  self : JITModule,
  func : JITFunction,
  _args : Array[Int64],
) -> Int64? {
  match self.context {
    Some(ctx) => {
      // Activate context for WASI calls
      ctx.activate()
      // Call using context-aware method
      // For now, only support () -> void signature (like _start)
      if func.has_result {
        Some(ctx.call_void_i64(func.exec_code.ptr))
      } else {
        ctx.call_void_void(func.exec_code.ptr)
        None
      }
    }
    None =>
      // Fallback to direct call (no context)
      func.call(_args)
  }
}
