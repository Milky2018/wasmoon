///|
/// Run a precompiled .cwasm file directly using the JIT runtime
fn run_cwasm(
  cwasm_path : String,
  invoke : String?,
  func_args : Array[String],
  _debug_config : DebugConfig,
) -> Unit {
  // Read the .cwasm file
  let bytes = @fs.read_file_to_bytes(cwasm_path) catch {
    IOError(e) => {
      println("Error: failed to read '\{cwasm_path}': \{e}")
      return
    }
  }
  // Convert Bytes to Array[Int]
  let byte_array : Array[Int] = []
  for i in 0..<bytes.length() {
    byte_array.push(bytes[i].to_int())
  }
  // Parse the precompiled module
  let precompiled = @cwasm.deserialize(byte_array) catch {
    e => {
      println("Error: failed to parse '\{cwasm_path}': \{e}")
      return
    }
  }
  // Build func_types array from the precompiled module
  // We need to determine (num_params, has_result) for each function
  // For now, assume the function signature based on the function index
  // Functions stored in precompiled are indexed by func_idx
  let func_types : Array[(Int, Bool)] = []
  for _ in precompiled.functions {
    // Default: assume (0, true) for void->result functions
    // This is a limitation - proper fix would store type info in .cwasm
    func_types.push((0, true))
  }
  // Load the JIT module
  let jit_module = @jit.JITModule::load(precompiled, func_types)
  match jit_module {
    Some(jm) => {
      // Determine which function to call
      let func_name = match invoke {
        Some(name) => name
        None => "_start"
      }
      // Find and call the function
      let jit_func = jm.get_func_by_name(func_name)
      match jit_func {
        Some(f) => {
          // Parse arguments (currently only support i64)
          let args : Array[Int64] = []
          for arg in func_args {
            let n = @strconv.parse_int64(arg) catch {
              _ => {
                println("Error: invalid argument '\{arg}'")
                jm.free()
                return
              }
            }
            args.push(n)
          }
          // Call the function
          let result = f.call(args)
          match result {
            Some(r) => println(r.to_string())
            None => ()
          }
        }
        None => println("Error: function '\{func_name}' not found")
      }
      // Free the JIT module
      jm.free()
    }
    None => println("Error: failed to load JIT module")
  }
}
