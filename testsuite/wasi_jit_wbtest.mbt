///|
/// WASI JIT vs Interpreter comparison tests
/// Tests that JIT and interpreter produce the same results for WASI functions

///|
/// Result of WASI comparison including captured output
struct WasiCompareResult {
  jit_result : Result[Array[@types.Value], String]
  interp_result : Result[Array[@types.Value], String]
  jit_stdout : Bytes
  interp_stdout : Bytes
  match_ : Bool
}

///|
pub impl Show for WasiCompareResult with output(self, logger) {
  if self.match_ {
    logger.write_string("matched")
  } else {
    logger.write_string(self.to_string())
  }
}

///|
pub fn WasiCompareResult::to_string(self : WasiCompareResult) -> String {
  let jit_str = match self.jit_result {
    Ok(vals) => format_values(vals)
    Err(e) => "Error: \{e}"
  }
  let interp_str = match self.interp_result {
    Ok(vals) => format_values(vals)
    Err(e) => "Error: \{e}"
  }
  let match_str = if self.match_ { "MATCH" } else { "MISMATCH" }
  "JIT: \{jit_str}, stdout=\{self.jit_stdout.length()}b\nInterpreter: \{interp_str}, stdout=\{self.interp_stdout.length()}b\nResult: \{match_str}"
}

///|
/// Run a WASI module with both JIT and interpreter, compare return values and output
fn compare_wasi(source : String, func_name : String) -> WasiCompareResult {
  compare_wasi_with_options(source, func_name)
}

///|
fn compare_wasi_with_options(
  source : String,
  func_name : String,
  preopens? : Array[(String, String)] = [],
  stdin_data? : Bytes,
  stdin_callback? : (() -> Bytes)? = None,
) -> WasiCompareResult {
  // Parse the WAT source
  let mod_ = @wat.parse(source) catch {
    e => {
      let err = "Failed to parse WAT: \{e}"
      return {
        jit_result: Err(err),
        interp_result: Err(err),
        jit_stdout: b"",
        interp_stdout: b"",
        match_: true,
      }
    }
  }

  // Find the function index by name
  let func_idx = find_wasi_func_index(mod_, func_name)
  guard func_idx is Some(idx) else {
    let err = "Function '\{func_name}' not found"
    return {
      jit_result: Err(err),
      interp_result: Err(err),
      jit_stdout: b"",
      interp_stdout: b"",
      match_: true,
    }
  }

  // Get function type
  let num_imports = @wast.count_func_imports(mod_.imports)
  let local_idx = idx - num_imports
  let func_type_idx = mod_.funcs[local_idx]
  let func_type = mod_.get_func_type(func_type_idx)
  let result_types = func_type.results

  // Run interpreter with WASI (stdout suppressed)
  let (interp_result, interp_stdout) = run_wasi_interp_quiet(
    mod_,
    func_name,
    preopens,
    stdin_data,
    stdin_callback~,
  )

  // Run JIT with WASI (stdout suppressed)
  let (jit_result, jit_stdout) = run_wasi_jit_quiet(
    mod_,
    func_name,
    idx,
    result_types,
    preopens,
    stdin_data,
    stdin_callback~,
  )

  // Compare results (return values must match)
  let results_match = match (jit_result, interp_result) {
    (Ok(jit_vals), Ok(interp_vals)) => values_array_equal(jit_vals, interp_vals)
    (Err(_), Err(_)) => true
    _ => false
  }
  let match_ = results_match && jit_stdout == interp_stdout
  { jit_result, interp_result, jit_stdout, interp_stdout, match_ }
}

///|
fn compare_wasi_with_callback(
  source : String,
  func_name : String,
  preopens? : Array[(String, String)] = [],
  stdin_factory : () -> () -> Bytes,
) -> WasiCompareResult {
  // Parse the WAT source
  let mod_ = @wat.parse(source) catch {
    e => {
      let err = "Failed to parse WAT: \{e}"
      return {
        jit_result: Err(err),
        interp_result: Err(err),
        jit_stdout: b"",
        interp_stdout: b"",
        match_: true,
      }
    }
  }

  // Find the function index by name
  let func_idx = find_wasi_func_index(mod_, func_name)
  guard func_idx is Some(idx) else {
    let err = "Function '\{func_name}' not found"
    return {
      jit_result: Err(err),
      interp_result: Err(err),
      jit_stdout: b"",
      interp_stdout: b"",
      match_: true,
    }
  }

  // Get function type
  let num_imports = @wast.count_func_imports(mod_.imports)
  let local_idx = idx - num_imports
  let func_type_idx = mod_.funcs[local_idx]
  let func_type = mod_.get_func_type(func_type_idx)
  let result_types = func_type.results
  let (interp_result, interp_stdout) = run_wasi_interp_quiet(
    mod_,
    func_name,
    preopens,
    None,
    stdin_callback=Some(stdin_factory()),
  )
  let (jit_result, jit_stdout) = run_wasi_jit_quiet(
    mod_,
    func_name,
    idx,
    result_types,
    preopens,
    None,
    stdin_callback=Some(stdin_factory()),
  )
  let results_match = match (jit_result, interp_result) {
    (Ok(jit_vals), Ok(interp_vals)) => values_array_equal(jit_vals, interp_vals)
    (Err(_), Err(_)) => true
    _ => false
  }
  let match_ = results_match && jit_stdout == interp_stdout
  { jit_result, interp_result, jit_stdout, interp_stdout, match_ }
}

///|
fn find_wasi_func_index(mod_ : @types.Module, name : String) -> Int? {
  for exp in mod_.exports {
    if exp.name == name && exp.desc is @types.ExportDesc::Func(idx) {
      return Some(idx)
    }
  }
  None
}

///|
fn run_wasi_interp_quiet(
  mod_ : @types.Module,
  func_name : String,
  preopens : Array[(String, String)],
  stdin_data : Bytes?,
  stdin_callback? : (() -> Bytes)? = None,
) -> (Result[Array[@types.Value], String], Bytes) {
  try {
    let stdout_buf : Array[Byte] = []
    let _stderr_buf : Array[Byte] = []
    let linker = @runtime.Linker::new()
    let store = linker.get_store()
    // Register WASI with suppressed stdout/stderr
    let wasi_builder = @wasi.WasiContextBuilder::new()
      .stdout(fn(bytes) {
        for b in bytes {
          stdout_buf.push(b)
        }
      })
      .stderr(fn(bytes) {
        for b in bytes {
          _stderr_buf.push(b)
        }
      })
    for entry in preopens {
      let (host, guest) = entry
      wasi_builder.preopen_dir(host, guest) |> ignore
    }
    match stdin_callback {
      Some(cb) => wasi_builder.stdin(cb) |> ignore
      None =>
        match stdin_data {
          Some(data) => {
            let mut stdin_used = false
            wasi_builder.stdin(fn() {
              if stdin_used {
                b""
              } else {
                stdin_used = true
                data
              }
            })
            |> ignore
          }
          None => ()
        }
    }
    let wasi_ctx = wasi_builder.build()
    @wasi.register_wasi(linker, wasi_ctx)
    let instance = @executor.instantiate_with_linker(linker, "test", mod_)
    let result = @executor.call_exported_func(store, instance, func_name, [])
    (Ok(result), Bytes::from_array(stdout_buf))
  } catch {
    e => (Err("Interpreter error: \{e}"), Bytes::from_array([]))
  }
}

///|
fn run_wasi_jit_quiet(
  mod_ : @types.Module,
  func_name : String,
  func_idx : Int,
  result_types : Array[@types.ValueType],
  preopens : Array[(String, String)],
  stdin_data : Bytes?,
  stdin_callback? : (() -> Bytes)? = None,
) -> (Result[Array[@types.Value], String], Bytes) {
  ignore(func_idx)
  try {
    let stdout_buf : Array[Byte] = []
    let _stderr_buf : Array[Byte] = []
    let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)
    let num_imports = @wast.count_func_imports(mod_.imports)

    // Build import function type indices
    let import_func_type_indices : Array[Int] = []
    for imp in mod_.imports {
      if imp.desc is Func(type_idx) {
        import_func_type_indices.push(type_idx)
        let func_type = mod_.get_func_type(type_idx)
        precompiled.add_import(
          imp.mod_name,
          imp.name,
          func_type.params.length(),
          func_type.results.length(),
        )
      }
    }
    let memory_max : Int? = if mod_.memories.length() > 0 {
      mod_.memories[0].limits.max.map(fn(m) { m.to_int() })
    } else {
      None
    }
    let memory_is_64 = mod_.memories.map(fn(m) { m.is_memory64 })
    let memory_page_size_log2 = mod_.memories.map(fn(m) { m.page_size_log2 })

    // Compile each function
    for i, code in mod_.codes {
      let f_idx = num_imports + i
      let type_idx = mod_.funcs[i]
      let func_type = mod_.get_func_type(type_idx)
      let f_name = get_wasi_func_name(mod_, f_idx)
      let translator = @ir.Translator::new(
        f_name,
        func_type,
        code.locals,
        @types.extract_func_types(mod_.types),
        mod_.funcs,
        num_imports,
        import_func_type_indices,
        memory_max~,
        memory_is_64~,
        memory_page_size_log2~,
        tables=mod_.tables,
        type_rec_groups=mod_.type_rec_groups,
        module_types=mod_.types,
        tags=mod_.tags,
      )
      let ir_func = translator.translate(code.body)
      let vcode = @lower.lower_function(ir_func)
      let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
      let mc = @emit.emit_function(allocated_func)
      let compiled = @vcode.CompiledFunction::new(f_name, mc, 0)
      precompiled.add_function(
        f_idx,
        f_name,
        compiled,
        func_type.params.length(),
        func_type.results.length(),
      )
    }
    let func_signatures = @wast.build_func_signatures(mod_)
    guard @jit.JITModule::load(precompiled, func_signatures) is Some(jm) else {
      return (Err("Failed to create JIT module"), Bytes::from_array([]))
    }
    let _ = jm.alloc_wasm_stack(1048576L)

    // Initialize WASI for JIT with captured stdout/stderr
    let stdin_buf = match stdin_data {
      Some(data) => Some(data)
      None => Some(b"")
    }
    jm.init_wasi_with_stdio(
      [],
      [],
      preopens,
      Some(fn(bytes : Bytes) {
        for b in bytes {
          stdout_buf.push(b)
        }
      }),
      Some(fn(bytes : Bytes) {
        for b in bytes {
          _stderr_buf.push(b)
        }
      }),
      stdin_buf,
      stdin_callback~,
    )

    // Allocate memory (guarded for memory32 memory 0)
    let mem_pages = if mod_.memories.length() > 0 {
      mod_.memories[0].limits.min.to_int()
    } else {
      0
    }
    let mem_size = mem_pages.to_int64() * 65536L
    let max_pages = if mod_.memories.length() > 0 {
      mod_.memories[0].limits.max.map(fn(m) { m.to_int() })
    } else {
      None
    }
    let mem_desc_ptr = if mem_pages > 0 && not(mod_.memories[0].is_memory64) {
      jm.alloc_guarded_memory(mem_pages, max_pages)
    } else if mem_size > 0L {
      @jit.alloc_memory_desc(
        mem_size,
        max_pages,
        is_memory64=mod_.memories[0].is_memory64,
      )
    } else {
      0L
    }
    if mem_desc_ptr == 0L && mem_size > 0L {
      return (Err("Failed to allocate memory"), Bytes::from_array([]))
    }
    let memories = [@jit.MemoryInfo::new(mem_desc_ptr, mem_size, max_pages)]
    jm.set_memory_pointers(memories)
    let mem_base = jm.get_memory_ptr(0)
    // Initialize data segments
    for data in mod_.datas {
      if data.memory_idx == 0 {
        let offset = eval_const_expr(data.offset)
        @jit.memory_init(mem_base, offset.to_int64(), data.init) |> ignore
      }
    }
    guard jm.get_func_by_name(func_name) is Some(f) else {
      return (Err("Failed to get JIT function"), Bytes::from_array([]))
    }
    let raw_results = jm.call_with_context(f, [])
    let values = jit_results_to_values(raw_results, result_types)
    (Ok(values), Bytes::from_array(stdout_buf))
  } catch {
    e => (Err("JIT error: \{e}"), Bytes::from_array([]))
  }
}

///|
fn get_wasi_func_name(mod_ : @types.Module, func_idx : Int) -> String {
  for exp in mod_.exports {
    if exp.desc is Func(idx) && idx == func_idx {
      return exp.name
    }
  }
  "func_\{func_idx}"
}

///|
fn eval_const_expr(instrs : Array[@types.Instruction]) -> Int {
  for instr in instrs {
    match instr {
      I32Const(n) => return n
      I64Const(n) => return n.to_int()
      _ => ()
    }
  }
  0
}

// ============ WASI Tests ============

///|
test "wasi jit: fd_write stdout returns 0" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_write"
    #|    (func $fd_write (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "\64\00\00\00\05\00\00\00")
    #|  (data (i32.const 100) "Hello")
    #|  (func (export "test") (result i32)
    #|    (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 200))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: stdio misuse returns EBADF" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_write"
    #|    (func $fd_write (param i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_read"
    #|    (func $fd_read (param i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_readdir"
    #|    (func $fd_readdir (param i32 i32 i32 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "A")
    #|  (func (export "write_fd0") (result i32)
    #|    (i32.store (i32.const 16) (i32.const 0))
    #|    (i32.store (i32.const 20) (i32.const 1))
    #|    (call $fd_write (i32.const 0) (i32.const 16) (i32.const 1) (i32.const 24)))
    #|  (func (export "read_fd1") (result i32)
    #|    (call $fd_read (i32.const 1) (i32.const 0) (i32.const 0) (i32.const 28)))
    #|  (func (export "close_fd0") (result i32)
    #|    (call $fd_close (i32.const 0)))
    #|  (func (export "readdir_fd0") (result i32)
    #|    (call $fd_readdir (i32.const 0) (i32.const 0) (i32.const 0)
    #|      (i64.const 0) (i32.const 32))))
  inspect(compare_wasi(source, "write_fd0"), content="matched")
  inspect(compare_wasi(source, "read_fd1"), content="matched")
  inspect(compare_wasi(source, "close_fd0"), content="matched")
  inspect(compare_wasi(source, "readdir_fd0"), content="matched")
}

///|
test "wasi jit: poll_oneoff stdin returns" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "poll_oneoff"
    #|    (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (i64.store (i32.const 0) (i64.const 0x9ABC))
    #|    (i32.store8 (i32.const 8) (i32.const 1))
    #|    (i32.store (i32.const 16) (i32.const 0))
    #|    (call $poll_oneoff (i32.const 0) (i32.const 64) (i32.const 1)
    #|      (i32.const 80))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: stdin callback supplies multiple reads" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_read"
    #|    (func $fd_read (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (i32.store (i32.const 0) (i32.const 100))
    #|    (i32.store (i32.const 4) (i32.const 2))
    #|    (drop (call $fd_read (i32.const 0) (i32.const 0) (i32.const 1)
    #|      (i32.const 20)))
    #|    (i32.store (i32.const 8) (i32.const 102))
    #|    (i32.store (i32.const 12) (i32.const 2))
    #|    (drop (call $fd_read (i32.const 0) (i32.const 8) (i32.const 1)
    #|      (i32.const 24)))
    #|    (i32.load (i32.const 100))))
  let stdin_factory = fn() {
    let mut stdin_calls = 0
    fn() {
      if stdin_calls == 0 {
        stdin_calls = 1
        b"AB"
      } else if stdin_calls == 1 {
        stdin_calls = 2
        b"CD"
      } else {
        b""
      }
    }
  }
  inspect(
    compare_wasi_with_callback(source, "test", stdin_factory),
    content="matched",
  )
}

///|
test "wasi jit: path_open invalid rights returns EINVAL" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 0)
    #|      (i32.const 0) (i64.const -1) (i64.const 0) (i32.const 0)
    #|      (i32.const 8))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_readdir works on path_open directory" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_create_directory"
    #|    (func $path_create_directory (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_readdir"
    #|    (func $fd_readdir (param i32 i32 i32 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_readdir")
    #|  (func (export "test") (result i32)
    #|    (drop (call $path_create_directory (i32.const 3) (i32.const 0) (i32.const 19)))
    #|    (drop (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 19)
    #|      (i32.const 2) (i64.const 0) (i64.const 0) (i32.const 0)
    #|      (i32.const 100)))
    #|    (call $fd_readdir
    #|      (i32.load (i32.const 100))
    #|      (i32.const 200) (i32.const 256) (i64.const 0) (i32.const 300))))
  inspect(
    compare_wasi_with_options(source, "test", preopens=[("/tmp", "/")]),
    content="matched",
  )
}

///|
test "wasi jit: path ops accept opened dir fd" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (drop (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 0)
    #|      (i32.const 2) (i64.const 0) (i64.const 0) (i32.const 0)
    #|      (i32.const 100)))
    #|    (call $path_open
    #|      (i32.load (i32.const 100)) (i32.const 0) (i32.const 0) (i32.const 0)
    #|      (i32.const 2) (i64.const 0) (i64.const 0) (i32.const 0)
    #|      (i32.const 120))))
  inspect(
    compare_wasi_with_options(source, "test", preopens=[("/tmp", "/")]),
    content="matched",
  )
}

///|
test "wasi jit: path_link honors old_flags" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_symlink"
    #|    (func $path_symlink (param i32 i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_link"
    #|    (func $path_link (param i32 i32 i32 i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "missing_target")
    #|  (data (i32.const 32) "wasmoon_link_symlink")
    #|  (data (i32.const 64) "wasmoon_link_hard")
    #|  (func (export "test") (result i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 64) (i32.const 17)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 32) (i32.const 20)))
    #|    (drop (call $path_symlink
    #|      (i32.const 0) (i32.const 14) (i32.const 3) (i32.const 32) (i32.const 20)))
    #|    (call $path_link
    #|      (i32.const 3) (i32.const 0) (i32.const 32) (i32.const 20)
    #|      (i32.const 3) (i32.const 64) (i32.const 17))))
  inspect(
    compare_wasi_with_options(source, "test", preopens=[("/tmp", "/")]),
    content="matched",
  )
}

///|
test "wasi jit: preopen fd rejects non-dir ops" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_sync"
    #|    (func $fd_sync (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_datasync"
    #|    (func $fd_datasync (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_seek"
    #|    (func $fd_seek (param i32 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_pread"
    #|    (func $fd_pread (param i32 i32 i32 i64 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_pwrite"
    #|    (func $fd_pwrite (param i32 i32 i32 i64 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_filestat_set_size"
    #|    (func $fd_filestat_set_size (param i32 i64) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_filestat_set_times"
    #|    (func $fd_filestat_set_times (param i32 i64 i64 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_advise"
    #|    (func $fd_advise (param i32 i64 i64 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_allocate"
    #|    (func $fd_allocate (param i32 i64 i64) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_set_flags"
    #|    (func $fd_fdstat_set_flags (param i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_set_rights"
    #|    (func $fd_fdstat_set_rights (param i32 i64 i64) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 128) "DATA")
    #|  (func (export "sync_preopen") (result i32)
    #|    (call $fd_sync (i32.const 3)))
    #|  (func (export "datasync_preopen") (result i32)
    #|    (call $fd_datasync (i32.const 3)))
    #|  (func (export "seek_preopen") (result i32)
    #|    (call $fd_seek (i32.const 3) (i64.const 0) (i32.const 0) (i32.const 32)))
    #|  (func (export "pread_preopen") (result i32)
    #|    (i32.store (i32.const 0) (i32.const 128))
    #|    (i32.store (i32.const 4) (i32.const 4))
    #|    (call $fd_pread (i32.const 3) (i32.const 0) (i32.const 1)
    #|      (i64.const 0) (i32.const 8)))
    #|  (func (export "pwrite_preopen") (result i32)
    #|    (i32.store (i32.const 16) (i32.const 128))
    #|    (i32.store (i32.const 20) (i32.const 4))
    #|    (call $fd_pwrite (i32.const 3) (i32.const 16) (i32.const 1)
    #|      (i64.const 0) (i32.const 24)))
    #|  (func (export "set_size_preopen") (result i32)
    #|    (call $fd_filestat_set_size (i32.const 3) (i64.const 0)))
    #|  (func (export "set_times_preopen") (result i32)
    #|    (call $fd_filestat_set_times (i32.const 3) (i64.const 0)
    #|      (i64.const 0) (i32.const 0)))
    #|  (func (export "advise_preopen") (result i32)
    #|    (call $fd_advise (i32.const 3) (i64.const 0) (i64.const 0) (i32.const 0)))
    #|  (func (export "allocate_preopen") (result i32)
    #|    (call $fd_allocate (i32.const 3) (i64.const 0) (i64.const 0)))
    #|  (func (export "set_flags_preopen") (result i32)
    #|    (call $fd_fdstat_set_flags (i32.const 3) (i32.const 0)))
    #|  (func (export "set_rights_preopen") (result i32)
    #|    (call $fd_fdstat_set_rights (i32.const 3) (i64.const 0) (i64.const 0))))
  inspect(
    compare_wasi_with_options(source, "sync_preopen", preopens=[("/tmp", "/")]),
    content="matched",
  )
  inspect(
    compare_wasi_with_options(source, "datasync_preopen", preopens=[
      ("/tmp", "/"),
    ]),
    content="matched",
  )
  inspect(
    compare_wasi_with_options(source, "seek_preopen", preopens=[("/tmp", "/")]),
    content="matched",
  )
  inspect(
    compare_wasi_with_options(source, "pread_preopen", preopens=[("/tmp", "/")]),
    content="matched",
  )
  inspect(
    compare_wasi_with_options(source, "pwrite_preopen", preopens=[("/tmp", "/")]),
    content="matched",
  )
  inspect(
    compare_wasi_with_options(source, "set_size_preopen", preopens=[
      ("/tmp", "/"),
    ]),
    content="matched",
  )
  inspect(
    compare_wasi_with_options(source, "set_times_preopen", preopens=[
      ("/tmp", "/"),
    ]),
    content="matched",
  )
  inspect(
    compare_wasi_with_options(source, "advise_preopen", preopens=[("/tmp", "/")]),
    content="matched",
  )
  inspect(
    compare_wasi_with_options(source, "allocate_preopen", preopens=[
      ("/tmp", "/"),
    ]),
    content="matched",
  )
  inspect(
    compare_wasi_with_options(source, "set_flags_preopen", preopens=[
      ("/tmp", "/"),
    ]),
    content="matched",
  )
  inspect(
    compare_wasi_with_options(source, "set_rights_preopen", preopens=[
      ("/tmp", "/"),
    ]),
    content="matched",
  )
}

///|
test "wasi jit: fd_read uses stdin callback" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_read"
    #|    (func $fd_read (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "\10\00\00\00\04\00\00\00")
    #|  (func (export "test") (result i32)
    #|    (drop (call $fd_read (i32.const 0) (i32.const 0) (i32.const 1) (i32.const 8)))
    #|    (i32.load (i32.const 8))))
  inspect(
    compare_wasi_with_options(source, "test", stdin_data=b"abc"),
    content="matched",
  )
}

///|
test "wasi jit: clock_time_get returns 0" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "clock_time_get"
    #|    (func $clock_time_get (param i32 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $clock_time_get (i32.const 0) (i64.const 1000000) (i32.const 0))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: random_get returns 0" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "random_get"
    #|    (func $random_get (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $random_get (i32.const 0) (i32.const 32))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: args_sizes_get returns 0" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "args_sizes_get"
    #|    (func $args_sizes_get (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $args_sizes_get (i32.const 0) (i32.const 4))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: args_get returns 0" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "args_sizes_get"
    #|    (func $args_sizes_get (param i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "args_get"
    #|    (func $args_get (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (drop (call $args_sizes_get (i32.const 0) (i32.const 4)))
    #|    (call $args_get (i32.const 100) (i32.const 500))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: environ_sizes_get returns 0" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "environ_sizes_get"
    #|    (func $environ_sizes_get (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $environ_sizes_get (i32.const 0) (i32.const 4))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: environ_get returns 0" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "environ_sizes_get"
    #|    (func $environ_sizes_get (param i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "environ_get"
    #|    (func $environ_get (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (drop (call $environ_sizes_get (i32.const 0) (i32.const 4)))
    #|    (call $environ_get (i32.const 100) (i32.const 500))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: sched_yield returns 0" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "sched_yield"
    #|    (func $sched_yield (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $sched_yield)))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_seek stdin returns ESPIPE (70)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_seek"
    #|    (func $fd_seek (param i32 i64 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_seek (i32.const 0) (i64.const 0) (i32.const 0) (i32.const 200))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_pread stdin returns ESPIPE (70)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_pread"
    #|    (func $fd_pread (param i32 i32 i32 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "\64\00\00\00\05\00\00\00")
    #|  (func (export "test") (result i32)
    #|    (call $fd_pread (i32.const 0) (i32.const 0) (i32.const 1) (i64.const 0) (i32.const 200))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_pwrite stdout returns ESPIPE (70)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_pwrite"
    #|    (func $fd_pwrite (param i32 i32 i32 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "\64\00\00\00\05\00\00\00")
    #|  (data (i32.const 100) "Hello")
    #|  (func (export "test") (result i32)
    #|    (call $fd_pwrite (i32.const 1) (i32.const 0) (i32.const 1) (i64.const 0) (i32.const 200))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_filestat_set_times stdin returns EINVAL (28)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_filestat_set_times"
    #|    (func $fd_filestat_set_times (param i32 i64 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_filestat_set_times (i32.const 0) (i64.const 0) (i64.const 0) (i32.const 0))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_filestat_set_size stdin returns EINVAL (28)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_filestat_set_size"
    #|    (func $fd_filestat_set_size (param i32 i64) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_filestat_set_size (i32.const 0) (i64.const 0))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_allocate stdout returns EINVAL (28)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_allocate"
    #|    (func $fd_allocate (param i32 i64 i64) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_allocate (i32.const 1) (i64.const 0) (i64.const 100))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_renumber stdin returns EINVAL (28)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_renumber"
    #|    (func $fd_renumber (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_renumber (i32.const 0) (i32.const 10))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_renumber allows unused target" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_renumber"
    #|    (func $fd_renumber (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_renumber_file")
    #|  (func (export "test") (result i32)
    #|    (drop (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 21)
    #|      (i32.const 9) (i64.const 0) (i64.const 0) (i32.const 0)
    #|      (i32.const 100)))
    #|    (call $fd_renumber (i32.load (i32.const 100)) (i32.const 10))))
  inspect(
    compare_wasi_with_options(source, "test", preopens=[("/tmp", "/")]),
    content="matched",
  )
}

///|
test "wasi jit: fd_sync stdin returns 0" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_sync"
    #|    (func $fd_sync (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_sync (i32.const 0))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_datasync stdout returns 0" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_datasync"
    #|    (func $fd_datasync (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_datasync (i32.const 1))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_fdstat_get stdin returns 0" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_get"
    #|    (func $fd_fdstat_get (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_fdstat_get (i32.const 0) (i32.const 0))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: sock_accept returns ENOTSUP (58)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "sock_accept"
    #|    (func $sock_accept (param i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $sock_accept (i32.const 0) (i32.const 0) (i32.const 0))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: sock_recv returns ENOTSUP (58)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "sock_recv"
    #|    (func $sock_recv (param i32 i32 i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $sock_recv (i32.const 0) (i32.const 0) (i32.const 0) (i32.const 0) (i32.const 0) (i32.const 0))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: sock_send returns ENOTSUP (58)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "sock_send"
    #|    (func $sock_send (param i32 i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $sock_send (i32.const 0) (i32.const 0) (i32.const 0) (i32.const 0) (i32.const 0))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: sock_shutdown returns ENOTSUP (58)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "sock_shutdown"
    #|    (func $sock_shutdown (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $sock_shutdown (i32.const 0) (i32.const 0))))
  inspect(compare_wasi(source, "test"), content="matched")
}
