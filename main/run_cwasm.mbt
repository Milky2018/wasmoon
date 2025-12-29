///|
/// Run a precompiled .cwasm file directly using the JIT runtime
fn run_cwasm(
  cwasm_path : String,
  invoke : String?,
  func_args : Array[String],
  _debug : Bool,
) -> Unit {
  // Read the .cwasm file
  let bytes = @fs.read_file_to_bytes(cwasm_path) catch {
    IOError(e) => {
      @logger.error("failed to read '\{cwasm_path}': \{e}")
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
      @logger.error("failed to parse '\{cwasm_path}': \{e}")
      return
    }
  }
  // Build func_signatures array from the precompiled module
  // For .cwasm files, we don't have full type info, so use default types
  let func_signatures : Array[
    (Array[@types.ValueType], Array[@types.ValueType]),
  ] = []
  for entry in precompiled.functions {
    // Create param_types array - default to I64 for all params
    let param_types : Array[@types.ValueType] = []
    for _ in 0..<entry.num_params {
      param_types.push(@types.ValueType::I64)
    }
    // Create result_types array - default to I64 for all results
    let result_types : Array[@types.ValueType] = []
    for _ in 0..<entry.num_results {
      result_types.push(@types.ValueType::I64)
    }
    func_signatures.push((param_types, result_types))
  }
  // Load the JIT module
  let jit_module = @jit.JITModule::load(precompiled, func_signatures)
  match jit_module {
    Some(jm) => {
      // Allocate linear memory (1 page = 64KB for now)
      let mem_size = 65536L // 64KB
      let mem_ptr = @jit.alloc_memory(mem_size)
      if mem_ptr == 0L {
        @logger.error("failed to allocate linear memory")
        // NOTE: No need to manually free - GC handles cleanup
        return
      }
      // Set memory in JIT context
      jm.set_memory(mem_ptr, mem_size)
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
                @logger.error("invalid argument '\{arg}'")
                // NOTE: Memory is freed by JITContext finalizer (GC-managed)
                return
              }
            }
            args.push(n)
          }
          // Call the function using context (for proper inter-function calls)
          let results = jm.call_with_context(f, args) catch {
            @jit.JITTrap(msg) => {
              @logger.error("JIT Trap: \{msg}")
              // NOTE: Memory is freed by JITContext finalizer (GC-managed)
              return
            }
          }
          if results.length() > 0 {
            let strs = results.map(fn(r) { r.to_string() })
            println(strs.join(" "))
          }
        }
        None => @logger.error("function '\{func_name}' not found")
      }
      // NOTE: Memory and JIT module are freed automatically by GC
    }
    None => @logger.error("failed to load JIT module")
  }
}
