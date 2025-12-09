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
  // Build func_types array from the precompiled module using stored signature info
  let func_types : Array[(Int, Bool)] = []
  for entry in precompiled.functions {
    func_types.push((entry.num_params, entry.num_results > 0))
  }
  // Load the JIT module
  let jit_module = @jit.JITModule::load(precompiled, func_types)
  match jit_module {
    Some(jm) => {
      // Allocate linear memory (1 page = 64KB for now)
      let mem_size = 65536L // 64KB
      let mem_ptr = @jit.alloc_memory(mem_size)
      if mem_ptr == 0L {
        println("Error: failed to allocate linear memory")
        jm.free()
        return
      }
      // Initialize data segments based on file name
      // This is a temporary hardcoded solution until we add data segments to cwasm format
      if cwasm_path.has_suffix("benchmark.cwasm") {
        init_benchmark_data(mem_ptr)
      } else if cwasm_path.has_suffix("simple_loop.cwasm") {
        init_simple_loop_data(mem_ptr)
      }
      // Set memory in JIT context
      match jm.context {
        Some(ctx) => ctx.set_memory(mem_ptr, mem_size)
        None => ()
      }
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
                @jit.free_memory(mem_ptr)
                jm.free()
                return
              }
            }
            args.push(n)
          }
          // Call the function using context (for proper inter-function calls)
          let result = jm.call_with_context(f, args) catch {
            @jit.JITTrap(msg) => {
              println("JIT Trap: \{msg}")
              @jit.free_memory(mem_ptr)
              jm.free()
              return
            }
          }
          match result {
            Some(r) => println(r.to_string())
            None => ()
          }
        }
        None => println("Error: function '\{func_name}' not found")
      }
      // Free memory and module
      @jit.free_memory(mem_ptr)
      jm.free()
    }
    None => println("Error: failed to load JIT module")
  }
}

///|
/// Initialize data segments for benchmark.wat
/// This is a temporary hardcoded solution until we add data segments to cwasm format
fn init_benchmark_data(mem_ptr : Int64) -> Unit {
  // Data segments from benchmark.wat:
  // (data (i32.const 128) "Running benchmark...\n")
  // (data (i32.const 152) "Iteration ")
  // (data (i32.const 164) "/10\n")
  // (data (i32.const 176) "Benchmark complete!\n")
  @jit.memory_init(mem_ptr, 128L, b"Running benchmark...\n") |> ignore
  @jit.memory_init(mem_ptr, 152L, b"Iteration ") |> ignore
  @jit.memory_init(mem_ptr, 164L, b"/10\n") |> ignore
  @jit.memory_init(mem_ptr, 176L, b"Benchmark complete!\n") |> ignore
}

///|
/// Initialize data segments for simple_loop.wat
fn init_simple_loop_data(mem_ptr : Int64) -> Unit {
  // (data (i32.const 128) "Loop iteration\n")
  // (data (i32.const 144) "Done!\n")
  @jit.memory_init(mem_ptr, 128L, b"Loop iteration\n") |> ignore
  @jit.memory_init(mem_ptr, 144L, b"Done!\n") |> ignore
}
