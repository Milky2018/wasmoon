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
}

///|
pub fn JITModule::new() -> JITModule {
  { functions: Map::new(), by_name: Map::new() }
}

///|
/// Load a precompiled module
pub fn JITModule::load(
  precompiled : @cwasm.PrecompiledModule,
  func_types : Array[(Int, Bool)], // (num_params, has_result) for each func_idx
) -> JITModule? {
  let jit_module = JITModule::new()
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
      }
      None => {
        // Failed to allocate, clean up
        for kv in jit_module.functions.iter() {
          kv.1.free()
        }
        return None
      }
    }
  }
  Some(jit_module)
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
}
