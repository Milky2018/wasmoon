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
pub impl Show for WasiCompareResult with fn output(self, logger) {
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
fn wasi_errno_from_result(result : Result[Array[@types.Value], String]) -> Int {
  match result {
    Ok(values) =>
      if values.length() == 1 {
        match values[0] {
          I32(errno) => errno
          _ => -2
        }
      } else {
        -3
      }
    Err(_) => -1
  }
}

///|
fn wasi_i32_from_result(result : Result[Array[@types.Value], String]) -> Int {
  match result {
    Ok(values) =>
      if values.length() == 1 {
        match values[0] {
          I32(value) => value
          _ => -2
        }
      } else {
        -3
      }
    Err(_) => -1
  }
}

///|
fn find_wasi_func_index(mod_ : @types.Module, name : String) -> Int? {
  for exp in mod_.exports {
    if exp.name == name && exp.desc is Func(idx) {
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
  func_name |> ignore
  try {
    let stdout_buf : Array[Byte] = []
    let stderr_buf : Array[Byte] = []
    let linker = @runtime.Linker::new()
    let store = linker.get_store()
    let wasi_builder = @wasi.WasiContextBuilder::new()
      .stdout(fn(bytes) {
        for b in bytes {
          stdout_buf.push(b)
        }
      })
      .stderr(fn(bytes) {
        for b in bytes {
          stderr_buf.push(b)
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
    guard @commands.compile_module_to_jit(mod_, false, false, 0, false)
      is Some((precompiled, debug_db)) else {
      return (Err("JIT compile returned unsupported"), Bytes::from_array([]))
    }
    let func_signatures = @wast.build_func_signatures(mod_)
    let external_imports = @wast.build_external_imports_for_jit(
      mod_, instance, store,
    )
    let jm = @jit.JITModule::load_with_imports(
      precompiled,
      func_signatures,
      external_imports,
      debug_db~,
    )
    @wast.register_instance_funcrefs_for_jit(jm, instance)
    @wast.install_jit_hostcall_dispatcher(jm, store, instance)
    jm.alloc_wasm_stack(1048576L) |> ignore
    jm.init_wasi_with_stdio(
      [],
      [],
      preopens,
      Some(fn(bytes) {
        for b in bytes {
          stdout_buf.push(b)
        }
      }),
      Some(fn(bytes) {
        for b in bytes {
          stderr_buf.push(b)
        }
      }),
      stdin_data,
      stdin_callback~,
    )
    guard @wast.init_jit_memories_from_store(instance, store, jm) is Some(_) else {
      return (Err("JIT memory initialization failed"), Bytes::from_array([]))
    }
    let globals_ptr = @wast.init_jit_globals_from_store(instance, store, jm)
    let use_subtype_indirect_check = true
    @wast.init_elem_segments(
      mod_,
      jm,
      instance,
      store,
      use_subtype_indirect_check~,
    )
    @wast.init_bulk_segments(
      mod_,
      jm,
      instance,
      store,
      use_subtype_indirect_check~,
    )
    @wast.sync_tables_to_jit(instance, store, jm, use_subtype_indirect_check~)
    let global_addrs : Array[Int] = []
    for addr in instance.global_addrs {
      global_addrs.push(addr)
    }
    let table_addrs : Array[Int] = []
    for addr in instance.table_addrs {
      table_addrs.push(addr)
    }
    let func_addrs : Array[Int] = []
    for addr in instance.func_addrs {
      func_addrs.push(addr)
    }
    let func_type_indices : Array[Int] = []
    for type_idx in instance.func_type_indices {
      func_type_indices.push(type_idx)
    }
    let canonical_type_indices : Array[Int] = []
    for canonical_idx in instance.canonical_type_indices {
      canonical_type_indices.push(canonical_idx)
    }
    let module_types : Array[@types.SubType] = []
    for subtype in mod_.types {
      module_types.push(subtype)
    }
    let module_rec_groups : Array[Int] = []
    for group in mod_.type_rec_groups {
      module_rec_groups.push(group)
    }
    let jit_ctx = @wast.JITModuleContext::new(
      jm, globals_ptr, global_addrs, table_addrs, func_addrs, func_type_indices,
      canonical_type_indices, module_types, module_rec_groups, use_subtype_indirect_check,
    )
    @wast.install_jit_interpcall_dispatcher(jit_ctx, store, instance)
    guard jm.get_func(func_idx) is Some(func) else {
      return (Err("JIT function \{func_idx} not loaded"), Bytes::from_array([]))
    }
    let raw_results = jm.call_with_context(func, [])
    (
      Ok(jit_results_to_values(raw_results, result_types)),
      Bytes::from_array(stdout_buf),
    )
  } catch {
    e => (Err("JIT error: \{e}"), Bytes::from_array([]))
  }
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
test "wasi jit: fd_write out-of-bounds iovec returns EFAULT" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_write"
    #|    (func $fd_write (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_write (i32.const 1) (i32.const 65532) (i32.const 1) (i32.const 0))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_write uses first non-empty iovec only" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_write"
    #|    (func $fd_write (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "\A0\00\00\00\00\00\00\00\B0\00\00\00\03\00\00\00\C0\00\00\00\03\00\00\00")
    #|  (data (i32.const 176) "abc")
    #|  (data (i32.const 192) "XYZ")
    #|  (func (export "test") (result i32)
    #|    (drop (call $fd_write
    #|      (i32.const 1) (i32.const 0) (i32.const 3) (i32.const 220)))
    #|    (i32.load (i32.const 220))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="3")
  inspect(wasi_errno_from_result(result.jit_result), content="3")
  inspect(result.interp_stdout.length(), content="3")
  inspect(result.jit_stdout.length(), content="3")
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
  let close_result = compare_wasi(source, "close_fd0")
  inspect(close_result.match_, content="true")
  inspect(wasi_errno_from_result(close_result.interp_result), content="0")
  inspect(wasi_errno_from_result(close_result.jit_result), content="0")
  inspect(compare_wasi(source, "readdir_fd0"), content="matched")
}

///|
test "wasi jit: closed stdin is no longer readable" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_read"
    #|    (func $fd_read (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (i32.store (i32.const 0) (i32.const 16))
    #|    (i32.store (i32.const 4) (i32.const 1))
    #|    (drop (call $fd_close (i32.const 0)))
    #|    (call $fd_read (i32.const 0) (i32.const 0) (i32.const 1) (i32.const 20))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="8")
  inspect(wasi_errno_from_result(result.jit_result), content="8")
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
test "wasi jit: poll_oneoff zero subscriptions returns EINVAL" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "poll_oneoff"
    #|    (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $poll_oneoff (i32.const 0) (i32.const 64) (i32.const 0)
    #|      (i32.const 80))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: poll_oneoff out-of-bounds subscription returns EFAULT" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "poll_oneoff"
    #|    (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $poll_oneoff (i32.const 65530) (i32.const 64) (i32.const 1)
    #|      (i32.const 80))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: poll_oneoff single relative clock writes nbytes=1" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "poll_oneoff"
    #|    (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    ;; single clock subscription: id=2 (cpu clock), relative timeout=0
    #|    (i64.store (i32.const 0) (i64.const 333))
    #|    (i32.store8 (i32.const 8) (i32.const 0))
    #|    (i32.store (i32.const 16) (i32.const 2))
    #|    (i64.store (i32.const 24) (i64.const 0))
    #|    (i64.store (i32.const 32) (i64.const 0))
    #|    (i32.store16 (i32.const 40) (i32.const 0))
    #|    (drop (call $poll_oneoff (i32.const 0) (i32.const 64) (i32.const 1)
    #|      (i32.const 128)))
    #|    (i32.wrap_i64 (i64.load (i32.const 80)))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="1")
  inspect(wasi_errno_from_result(result.jit_result), content="1")
}

///|
test "wasi jit: poll_oneoff rejects unknown subclockflags bits with EINVAL" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "poll_oneoff"
    #|    (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (i64.store (i32.const 0) (i64.const 777))
    #|    (i32.store8 (i32.const 8) (i32.const 0))
    #|    (i32.store (i32.const 16) (i32.const 1))
    #|    (i64.store (i32.const 24) (i64.const 0))
    #|    (i64.store (i32.const 32) (i64.const 0))
    #|    (i32.store16 (i32.const 40) (i32.const 2))
    #|    (call $poll_oneoff
    #|      (i32.const 0) (i32.const 64) (i32.const 1) (i32.const 128))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="28")
  inspect(wasi_errno_from_result(result.jit_result), content="28")
}

///|
test "wasi jit: poll_oneoff fd_read reports remaining file bytes" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_write"
    #|    (func $fd_write (param i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "poll_oneoff"
    #|    (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 32) "abc")
    #|  (data (i32.const 64) "wasmoon_poll_nbytes.txt")
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (local $write_fd i32)
    #|    (local $read_fd i32)
    #|    (local $nbytes i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 64) (i32.const 23)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 64) (i32.const 23)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 200)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (local.set $write_fd (i32.load (i32.const 200)))
    #|    (i32.store (i32.const 128) (i32.const 32))
    #|    (i32.store (i32.const 132) (i32.const 3))
    #|    (local.set $errno
    #|      (call $fd_write
    #|        (local.get $write_fd) (i32.const 128) (i32.const 1) (i32.const 220)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (drop (call $fd_close (local.get $write_fd)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 64) (i32.const 23)
    #|        (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 0)
    #|        (i32.const 204)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (local.set $read_fd (i32.load (i32.const 204)))
    #|    ;; fd_read subscription
    #|    (i64.store (i32.const 0) (i64.const 555))
    #|    (i32.store8 (i32.const 8) (i32.const 1))
    #|    (i32.store (i32.const 12) (local.get $read_fd))
    #|    (local.set $errno
    #|      (call $poll_oneoff
    #|        (i32.const 0) (i32.const 256) (i32.const 1) (i32.const 240)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (local.set $nbytes (i32.wrap_i64 (i64.load (i32.const 272))))
    #|    (drop (call $fd_close (local.get $read_fd)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 64) (i32.const 23)))
    #|    (local.get $nbytes)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_i32_from_result(result.interp_result), content="3")
  inspect(wasi_i32_from_result(result.jit_result), content="3")
}

///|
test "wasi jit: poll_oneoff keeps expired realtime clock when fd is ready" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "poll_oneoff"
    #|    (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    ;; sub[0] = clock(realtime, absolute, timeout=1e17ns)
    #|    (i64.store (i32.const 0) (i64.const 111))
    #|    (i32.store8 (i32.const 8) (i32.const 0))
    #|    (i32.store (i32.const 16) (i32.const 0))
    #|    (i64.store (i32.const 24) (i64.const 100000000000000000))
    #|    (i32.store16 (i32.const 40) (i32.const 1))
    #|    ;; sub[1] = fd_write(stdout)
    #|    (i64.store (i32.const 48) (i64.const 222))
    #|    (i32.store8 (i32.const 56) (i32.const 2))
    #|    (i32.store (i32.const 60) (i32.const 1))
    #|    (drop (call $poll_oneoff (i32.const 0) (i32.const 96) (i32.const 2)
    #|      (i32.const 80)))
    #|    (i32.load (i32.const 80))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="2")
  inspect(wasi_errno_from_result(result.jit_result), content="2")
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
test "wasi jit: path_open ignores unknown rights bits and still validates dirfd" {
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
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="8")
  inspect(wasi_errno_from_result(result.jit_result), content="8")
}

///|
test "wasi jit: path_open rejects sync fdflags with ENOTSUP" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_sync_open.txt")
    #|  (func (export "test") (result i32)
    #|    (local $fd i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 23)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 22)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 100)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (local.set $fd (i32.load (i32.const 100)))
    #|    (drop (call $fd_close (local.get $fd)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 22)
    #|        (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 16)
    #|        (i32.const 104)))
    #|    (if (i32.eq (local.get $errno) (i32.const 0))
    #|      (then
    #|        (drop (call $fd_close (i32.load (i32.const 104))))))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 22)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="58")
  inspect(wasi_errno_from_result(result.jit_result), content="58")
}

///|
test "wasi jit: path_open traps on unknown dirflags bits" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_unknown_dirflags.txt")
    #|  (func (export "test") (result i32)
    #|    (local $fd i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 30)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 30)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 100)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (local.set $fd (i32.load (i32.const 100)))
    #|    (drop (call $fd_close (local.get $fd)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 2) (i32.const 0) (i32.const 30)
    #|        (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 0)
    #|        (i32.const 104)))
    #|    (if (i32.eq (local.get $errno) (i32.const 0))
    #|      (then
    #|        (drop (call $fd_close (i32.load (i32.const 104))))))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 30)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
}

///|
test "wasi jit: path_open traps on unknown oflags bits" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_unknown_oflags.txt")
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 26)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 26)
    #|        (i32.const 16) (i64.const 2) (i64.const 0) (i32.const 0)
    #|        (i32.const 100)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 26)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
}

///|
test "wasi jit: path_open traps on unknown fdflags bits" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_unknown_fdflags.txt")
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 27)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 27)
    #|        (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 32)
    #|        (i32.const 100)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 27)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
}

///|
test "wasi jit: path_open with non-directory dirfd returns NOTDIR" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_notdir_base.txt")
    #|  (data (i32.const 64) "child.txt")
    #|  (func (export "test") (result i32)
    #|    (local $fd i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 27)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 27)
    #|        (i32.const 9) (i64.const 66) (i64.const 0) (i32.const 0)
    #|        (i32.const 100)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (local.set $fd (i32.load (i32.const 100)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (local.get $fd) (i32.const 0) (i32.const 64) (i32.const 9)
    #|        (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 0)
    #|        (i32.const 104)))
    #|    (drop (call $fd_close (local.get $fd)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 27)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="54")
  inspect(wasi_errno_from_result(result.jit_result), content="54")
}

///|
test "wasi jit: fd_prestat_dir_name returns NOTDIR for regular file fd" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_prestat_dir_name"
    #|    (func $fd_prestat_dir_name (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_prestat_notdir.txt")
    #|  (func (export "test") (result i32)
    #|    (local $fd i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 29)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 29)
    #|        (i32.const 9) (i64.const 66) (i64.const 0) (i32.const 0)
    #|        (i32.const 100)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (local.set $fd (i32.load (i32.const 100)))
    #|    (local.set $errno
    #|      (call $fd_prestat_dir_name (local.get $fd) (i32.const 200) (i32.const 8)))
    #|    (drop (call $fd_close (local.get $fd)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 29)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="54")
  inspect(wasi_errno_from_result(result.jit_result), content="54")
}

///|
test "wasi jit: path_open write-only rights without create is writable" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_pwrite"
    #|    (func $fd_pwrite (param i32 i32 i32 i64 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_rights_open.txt")
    #|  (func (export "test") (result i32)
    #|    (local $fd i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 27)))
    #|    (drop (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 27)
    #|      (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|      (i32.const 100)))
    #|    (drop (call $fd_close (i32.load (i32.const 100))))
    #|    (drop (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 27)
    #|      (i32.const 0) (i64.const 64) (i64.const 0) (i32.const 0)
    #|      (i32.const 104)))
    #|    (local.set $fd (i32.load (i32.const 104)))
    #|    (i32.store (i32.const 200) (i32.const 300))
    #|    (i32.store (i32.const 204) (i32.const 1))
    #|    (i32.store8 (i32.const 300) (i32.const 65))
    #|    (local.set $errno
    #|      (call $fd_pwrite
    #|        (local.get $fd) (i32.const 200) (i32.const 1) (i64.const 0)
    #|        (i32.const 400)))
    #|    (drop (call $fd_close (local.get $fd)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 27)))
    #|    (local.get $errno)))
  inspect(
    compare_wasi_with_options(source, "test", preopens=[("/tmp", "/")]),
    content="matched",
  )
}

///|
test "wasi jit: path_open rejects symlink escape outside preopen" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_remove_directory"
    #|    (func $path_remove_directory (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_symlink"
    #|    (func $path_symlink (param i32 i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "../")
    #|  (data (i32.const 16) "caplk_escape")
    #|  (data (i32.const 48) "caplk_escape/etc/passwd")
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_remove_directory (i32.const 3) (i32.const 16) (i32.const 12)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 16) (i32.const 12)))
    #|    (drop (call $path_symlink
    #|      (i32.const 0) (i32.const 3) (i32.const 3) (i32.const 16) (i32.const 12)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 48) (i32.const 23)
    #|        (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 0)
    #|        (i32.const 120)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 16) (i32.const 12)))
    #|    (drop (call $path_remove_directory (i32.const 3) (i32.const 16) (i32.const 12)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="63")
  inspect(wasi_errno_from_result(result.jit_result), content="63")
}

///|
test "wasi jit: path_unlink_file can remove escaped symlink entry" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_symlink"
    #|    (func $path_symlink (param i32 i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "caplk_escape_unlink_jit")
    #|  (data (i32.const 64) "../")
    #|  (func (export "test") (result i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 22)))
    #|    (drop (call $path_symlink
    #|      (i32.const 64) (i32.const 3) (i32.const 3) (i32.const 0) (i32.const 23)))
    #|    (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 23))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="0")
  inspect(wasi_errno_from_result(result.jit_result), content="0")
}

///|
test "wasi jit: path_open lexical escapes return EPERM" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "/wasmoon_abs_path_probe")
    #|  (data (i32.const 64) "../wasmoon_escape_probe")
    #|  (func (export "test_abs") (result i32)
    #|    (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 22)
    #|      (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 0)
    #|      (i32.const 200)))
    #|  (func (export "test_dotdot") (result i32)
    #|    (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 64) (i32.const 22)
    #|      (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 0)
    #|      (i32.const 204))))
  let abs_result = compare_wasi_with_options(source, "test_abs", preopens=[
    ("/tmp", "/"),
  ])
  inspect(abs_result.match_, content="true")
  inspect(wasi_errno_from_result(abs_result.interp_result), content="63")
  inspect(wasi_errno_from_result(abs_result.jit_result), content="63")

  let dotdot_result = compare_wasi_with_options(source, "test_dotdot", preopens=[
    ("/tmp", "/"),
  ])
  inspect(dotdot_result.match_, content="true")
  inspect(wasi_errno_from_result(dotdot_result.interp_result), content="63")
  inspect(wasi_errno_from_result(dotdot_result.jit_result), content="63")
}

///|
test "wasi jit: path_open empty path returns ENOENT" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 0)
    #|      (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 0)
    #|      (i32.const 200))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="44")
  inspect(wasi_errno_from_result(result.jit_result), content="44")
}

///|
test "wasi jit: path_open trailing slash on regular file returns ENOENT" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_trailing_path.txt")
    #|  (data (i32.const 64) "wasmoon_jit_trailing_path.txt/")
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 29)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 29)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 200)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (drop (call $fd_close (i32.load (i32.const 200))))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 64) (i32.const 30)
    #|        (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 0)
    #|        (i32.const 204)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 29)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="44")
  inspect(wasi_errno_from_result(result.jit_result), content="44")
}

///|
test "wasi jit: path_filestat_get trailing slash on regular file returns ENOENT" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_filestat_get"
    #|    (func $path_filestat_get (param i32 i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_trailing_path.txt")
    #|  (data (i32.const 64) "wasmoon_jit_trailing_path.txt/")
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 29)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 29)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 200)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (drop (call $fd_close (i32.load (i32.const 200))))
    #|    (local.set $errno
    #|      (call $path_filestat_get
    #|        (i32.const 3) (i32.const 0) (i32.const 64) (i32.const 30)
    #|        (i32.const 300)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 29)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="44")
  inspect(wasi_errno_from_result(result.jit_result), content="44")
}

///|
test "wasi jit: path_filestat_get traps on unknown lookupflags bits" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_filestat_get"
    #|    (func $path_filestat_get (param i32 i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_filestat_lookupflags.txt")
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 34)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 34)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 200)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (drop (call $fd_close (i32.load (i32.const 200))))
    #|    (local.set $errno
    #|      (call $path_filestat_get
    #|        (i32.const 3) (i32.const 2) (i32.const 0) (i32.const 34)
    #|        (i32.const 300)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 34)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
}

///|
test "wasi jit: path_filestat_set_times trailing slash on regular file returns ENOENT" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_filestat_set_times"
    #|    (func $path_filestat_set_times (param i32 i32 i32 i32 i64 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_trailing_path.txt")
    #|  (data (i32.const 64) "wasmoon_jit_trailing_path.txt/")
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 29)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 29)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 200)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (drop (call $fd_close (i32.load (i32.const 200))))
    #|    (local.set $errno
    #|      (call $path_filestat_set_times
    #|        (i32.const 3) (i32.const 0) (i32.const 64) (i32.const 30)
    #|        (i64.const 0) (i64.const 0) (i32.const 0)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 29)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="44")
  inspect(wasi_errno_from_result(result.jit_result), content="44")
}

///|
test "wasi jit: path_filestat_set_times rejects conflicting fst_flags with EINVAL" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_filestat_set_times"
    #|    (func $path_filestat_set_times (param i32 i32 i32 i32 i64 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_path_settimes_conflict.txt")
    #|  (func (export "test_atim") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 35)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 35)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 200)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (drop (call $fd_close (i32.load (i32.const 200))))
    #|    (local.set $errno
    #|      (call $path_filestat_set_times
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 35)
    #|        (i64.const 0) (i64.const 0) (i32.const 3)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 35)))
    #|    (local.get $errno))
    #|  (func (export "test_mtim") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 35)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 35)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 200)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (drop (call $fd_close (i32.load (i32.const 200))))
    #|    (local.set $errno
    #|      (call $path_filestat_set_times
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 35)
    #|        (i64.const 0) (i64.const 0) (i32.const 12)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 35)))
    #|    (local.get $errno)))
  let atim_result = compare_wasi_with_options(source, "test_atim", preopens=[
    ("/tmp", "/"),
  ])
  inspect(atim_result.match_, content="true")
  inspect(wasi_errno_from_result(atim_result.interp_result), content="28")
  inspect(wasi_errno_from_result(atim_result.jit_result), content="28")
  let mtim_result = compare_wasi_with_options(source, "test_mtim", preopens=[
    ("/tmp", "/"),
  ])
  inspect(mtim_result.match_, content="true")
  inspect(wasi_errno_from_result(mtim_result.interp_result), content="28")
  inspect(wasi_errno_from_result(mtim_result.jit_result), content="28")
}

///|
test "wasi jit: path_filestat_set_times traps on unknown lookupflags bits" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_filestat_set_times"
    #|    (func $path_filestat_set_times (param i32 i32 i32 i32 i64 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_settimes_lookupflags.txt")
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 34)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 34)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 200)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (drop (call $fd_close (i32.load (i32.const 200))))
    #|    (local.set $errno
    #|      (call $path_filestat_set_times
    #|        (i32.const 3) (i32.const 2) (i32.const 0) (i32.const 34)
    #|        (i64.const 0) (i64.const 0) (i32.const 0)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 34)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
}

///|
test "wasi jit: path_open trailing slash can open symlinked directory with nofollow" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_symlink"
    #|    (func $path_symlink (param i32 i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_trailing_link_dir")
    #|  (data (i32.const 64) "wasmoon_jit_trailing_link_dir/")
    #|  (data (i32.const 128) "../tmp")
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 29)))
    #|    (local.set $errno
    #|      (call $path_symlink
    #|        (i32.const 128) (i32.const 6) (i32.const 3) (i32.const 0) (i32.const 29)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 64) (i32.const 30)
    #|        (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 0)
    #|        (i32.const 200)))
    #|    (if (i32.eq (local.get $errno) (i32.const 0))
    #|      (then (drop (call $fd_close (i32.load (i32.const 200))))))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 29)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="0")
  inspect(wasi_errno_from_result(result.jit_result), content="0")
}

///|
test "wasi jit: path_open with embedded NUL returns EINVAL" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_nul_path.txt")
    #|  (data (i32.const 64) "wasmoon_jit_nul_path.txt\00")
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 24)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 24)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 200)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (drop (call $fd_close (i32.load (i32.const 200))))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 64) (i32.const 25)
    #|        (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 0)
    #|        (i32.const 204)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 24)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="28")
  inspect(wasi_errno_from_result(result.jit_result), content="28")
}

///|
test "wasi jit: path_open with invalid UTF-8 returns EILSEQ" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "\ff")
    #|  (func (export "test") (result i32)
    #|    (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 1)
    #|      (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 0)
    #|      (i32.const 200))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="25")
  inspect(wasi_errno_from_result(result.jit_result), content="25")
}

///|
test "wasi jit: path_symlink rejects absolute old_path with EPERM" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_symlink"
    #|    (func $path_symlink (param i32 i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "/")
    #|  (data (i32.const 16) "wasmoon_abs_target")
    #|  (func (export "test") (result i32)
    #|    (call $path_symlink
    #|      (i32.const 0) (i32.const 1) (i32.const 3) (i32.const 16) (i32.const 18))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="63")
  inspect(wasi_errno_from_result(result.jit_result), content="63")
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
test "wasi jit: fd_readdir writes truncated dirent header" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_create_directory"
    #|    (func $path_create_directory (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_remove_directory"
    #|    (func $path_remove_directory (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_readdir"
    #|    (func $fd_readdir (param i32 i32 i32 i64 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_readdir_trunc")
    #|  (func (export "test") (result i32)
    #|    (local $fd i32)
    #|    (drop (call $path_remove_directory (i32.const 3) (i32.const 0) (i32.const 24)))
    #|    (drop (call $path_create_directory (i32.const 3) (i32.const 0) (i32.const 24)))
    #|    (drop (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 24)
    #|      (i32.const 2) (i64.const 0) (i64.const 0) (i32.const 0)
    #|      (i32.const 100)))
    #|    (local.set $fd (i32.load (i32.const 100)))
    #|    (drop (call $fd_readdir
    #|      (local.get $fd) (i32.const 200) (i32.const 10) (i64.const 0) (i32.const 400)))
    #|    (drop (call $fd_close (local.get $fd)))
    #|    (drop (call $path_remove_directory (i32.const 3) (i32.const 0) (i32.const 24)))
    #|    (i32.load (i32.const 400))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="10")
  inspect(wasi_errno_from_result(result.jit_result), content="10")
}

///|
test "wasi jit: fd_readdir on regular file returns EBADF (8)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_readdir"
    #|    (func $fd_readdir (param i32 i32 i32 i64 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_readdir_file.txt")
    #|  (func (export "test") (result i32)
    #|    (local $fd i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 27)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 27)
    #|        (i32.const 9) (i64.const 66) (i64.const 0) (i32.const 0)
    #|        (i32.const 100)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (local.set $fd (i32.load (i32.const 100)))
    #|    (local.set $errno
    #|      (call $fd_readdir
    #|        (local.get $fd) (i32.const 200) (i32.const 64) (i64.const 0)
    #|        (i32.const 400)))
    #|    (drop (call $fd_close (local.get $fd)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 27)))
    #|    (local.get $errno)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="8")
  inspect(wasi_errno_from_result(result.jit_result), content="8")
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
test "wasi jit: path_link rejects LOOKUPFLAGS_SYMLINK_FOLLOW" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_link"
    #|    (func $path_link (param i32 i32 i32 i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_link_source")
    #|  (data (i32.const 32) "wasmoon_link_hard")
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 32) (i32.const 17)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 19)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 19)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 100)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (drop (call $fd_close (i32.load (i32.const 100))))
    #|    (call $path_link
    #|      (i32.const 3) (i32.const 1) (i32.const 0) (i32.const 19)
    #|      (i32.const 3) (i32.const 32) (i32.const 17))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="28")
  inspect(wasi_errno_from_result(result.jit_result), content="28")
}

///|
test "wasi jit: path_link traps on unknown lookupflags bits" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_link"
    #|    (func $path_link (param i32 i32 i32 i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_link_source")
    #|  (data (i32.const 32) "wasmoon_link_hard")
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 32) (i32.const 17)))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 19)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 19)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 100)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (drop (call $fd_close (i32.load (i32.const 100))))
    #|    (call $path_link
    #|      (i32.const 3) (i32.const 2) (i32.const 0) (i32.const 19)
    #|      (i32.const 3) (i32.const 32) (i32.const 17))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
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
test "wasi jit: clock_time_get process/thread cpu clocks return EBADF (8)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "clock_time_get"
    #|    (func $clock_time_get (param i32 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "process_clock") (result i32)
    #|    (call $clock_time_get (i32.const 2) (i64.const 0) (i32.const 0)))
    #|  (func (export "thread_clock") (result i32)
    #|    (call $clock_time_get (i32.const 3) (i64.const 0) (i32.const 0))))
  let process_result = compare_wasi(source, "process_clock")
  inspect(process_result.match_, content="true")
  inspect(wasi_errno_from_result(process_result.interp_result), content="8")
  inspect(wasi_errno_from_result(process_result.jit_result), content="8")
  let thread_result = compare_wasi(source, "thread_clock")
  inspect(thread_result.match_, content="true")
  inspect(wasi_errno_from_result(thread_result.interp_result), content="8")
  inspect(wasi_errno_from_result(thread_result.jit_result), content="8")
}

///|
test "wasi jit: clock_time_get traps on invalid clock id enum" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "clock_time_get"
    #|    (func $clock_time_get (param i32 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $clock_time_get (i32.const 999) (i64.const 0) (i32.const 0))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
}

///|
test "wasi jit: clock_res_get process/thread cpu clocks return EBADF (8)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "clock_res_get"
    #|    (func $clock_res_get (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "process_clock") (result i32)
    #|    (call $clock_res_get (i32.const 2) (i32.const 0)))
    #|  (func (export "thread_clock") (result i32)
    #|    (call $clock_res_get (i32.const 3) (i32.const 0))))
  let process_result = compare_wasi(source, "process_clock")
  inspect(process_result.match_, content="true")
  inspect(wasi_errno_from_result(process_result.interp_result), content="8")
  inspect(wasi_errno_from_result(process_result.jit_result), content="8")
  let thread_result = compare_wasi(source, "thread_clock")
  inspect(thread_result.match_, content="true")
  inspect(wasi_errno_from_result(thread_result.interp_result), content="8")
  inspect(wasi_errno_from_result(thread_result.jit_result), content="8")
}

///|
test "wasi jit: clock_res_get traps on invalid clock id enum" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "clock_res_get"
    #|    (func $clock_res_get (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $clock_res_get (i32.const 999) (i32.const 0))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
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
test "wasi jit: proc_raise returns ENOTSUP (58)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "proc_raise"
    #|    (func $proc_raise (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $proc_raise (i32.const 2))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="58")
  inspect(wasi_errno_from_result(result.jit_result), content="58")
}

///|
test "wasi jit: proc_raise traps on invalid signal enum" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "proc_raise"
    #|    (func $proc_raise (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $proc_raise (i32.const 255))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
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
test "wasi jit: fd_seek traps on invalid whence enum" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_seek"
    #|    (func $fd_seek (param i32 i64 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_seek (i32.const 0) (i64.const 0) (i32.const 3) (i32.const 200))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
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
test "wasi jit: fd_pread stdout returns EBADF (8)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_pread"
    #|    (func $fd_pread (param i32 i32 i32 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "\64\00\00\00\05\00\00\00")
    #|  (func (export "test") (result i32)
    #|    (call $fd_pread (i32.const 1) (i32.const 0) (i32.const 1) (i64.const 0) (i32.const 200))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_pread stderr returns EBADF (8)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_pread"
    #|    (func $fd_pread (param i32 i32 i32 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "\64\00\00\00\05\00\00\00")
    #|  (func (export "test") (result i32)
    #|    (call $fd_pread (i32.const 2) (i32.const 0) (i32.const 1) (i64.const 0) (i32.const 200))))
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
test "wasi jit: fd_pwrite stdin returns EBADF (8)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_pwrite"
    #|    (func $fd_pwrite (param i32 i32 i32 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "\64\00\00\00\05\00\00\00")
    #|  (data (i32.const 100) "Hello")
    #|  (func (export "test") (result i32)
    #|    (call $fd_pwrite (i32.const 0) (i32.const 0) (i32.const 1) (i64.const 0) (i32.const 200))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_filestat_set_times stdin returns EBADF (8)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_filestat_set_times"
    #|    (func $fd_filestat_set_times (param i32 i64 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_filestat_set_times (i32.const 0) (i64.const 0) (i64.const 0) (i32.const 0))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="8")
  inspect(wasi_errno_from_result(result.jit_result), content="8")
}

///|
test "wasi jit: fd_filestat_set_times rejects conflicting fst_flags with EINVAL" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_filestat_set_times"
    #|    (func $fd_filestat_set_times (param i32 i64 i64 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $path_unlink_file (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $fd_close (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_jit_fd_settimes_conflict.txt")
    #|  (func (export "test_atim") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 33)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 33)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 100)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (local.set $errno
    #|      (call $fd_filestat_set_times
    #|        (i32.load (i32.const 100)) (i64.const 0) (i64.const 0) (i32.const 3)))
    #|    (drop (call $fd_close (i32.load (i32.const 100))))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 33)))
    #|    (local.get $errno))
    #|  (func (export "test_mtim") (result i32)
    #|    (local $errno i32)
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 33)))
    #|    (local.set $errno
    #|      (call $path_open
    #|        (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 33)
    #|        (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0)
    #|        (i32.const 100)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (local.get $errno))))
    #|    (local.set $errno
    #|      (call $fd_filestat_set_times
    #|        (i32.load (i32.const 100)) (i64.const 0) (i64.const 0) (i32.const 12)))
    #|    (drop (call $fd_close (i32.load (i32.const 100))))
    #|    (drop (call $path_unlink_file (i32.const 3) (i32.const 0) (i32.const 33)))
    #|    (local.get $errno)))
  let atim_result = compare_wasi_with_options(source, "test_atim", preopens=[
    ("/tmp", "/"),
  ])
  inspect(atim_result.match_, content="true")
  inspect(wasi_errno_from_result(atim_result.interp_result), content="28")
  inspect(wasi_errno_from_result(atim_result.jit_result), content="28")
  let mtim_result = compare_wasi_with_options(source, "test_mtim", preopens=[
    ("/tmp", "/"),
  ])
  inspect(mtim_result.match_, content="true")
  inspect(wasi_errno_from_result(mtim_result.interp_result), content="28")
  inspect(wasi_errno_from_result(mtim_result.jit_result), content="28")
}

///|
test "wasi jit: fd_filestat_set_size stdin returns EBADF (8)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_filestat_set_size"
    #|    (func $fd_filestat_set_size (param i32 i64) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_filestat_set_size (i32.const 0) (i64.const 0))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="8")
  inspect(wasi_errno_from_result(result.jit_result), content="8")
}

///|
test "wasi jit: fd_allocate stdout returns EBADF (8)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_allocate"
    #|    (func $fd_allocate (param i32 i64 i64) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_allocate (i32.const 1) (i64.const 0) (i64.const 100))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="8")
  inspect(wasi_errno_from_result(result.jit_result), content="8")
}

///|
test "wasi jit: fd_allocate regular file returns ENOTSUP (58)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_allocate"
    #|    (func $fd_allocate (param i32 i64 i64) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_allocate_file")
    #|  (func (export "test") (result i32)
    #|    (drop (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 21)
    #|      (i32.const 9) (i64.const 2) (i64.const 0) (i32.const 0)
    #|      (i32.const 100)))
    #|    (call $fd_allocate (i32.load (i32.const 100)) (i64.const 0) (i64.const 32))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="58")
  inspect(wasi_errno_from_result(result.jit_result), content="58")
}

///|
test "wasi jit: fd_advise traps on invalid advice enum" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_advise"
    #|    (func $fd_advise (param i32 i64 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_advise_invalid")
    #|  (func (export "test") (result i32)
    #|    (drop (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 22)
    #|      (i32.const 9) (i64.const 0) (i64.const 0) (i32.const 0)
    #|      (i32.const 100)))
    #|    (call $fd_advise
    #|      (i32.load (i32.const 100)) (i64.const 0) (i64.const 16) (i32.const 123))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
}

///|
test "wasi jit: fd_renumber stdin to missing target returns EBADF (8)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_renumber"
    #|    (func $fd_renumber (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_renumber (i32.const 0) (i32.const 10))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="8")
  inspect(wasi_errno_from_result(result.jit_result), content="8")
}

///|
test "wasi jit: fd_renumber stdin identity succeeds (0)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_renumber"
    #|    (func $fd_renumber (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_renumber (i32.const 0) (i32.const 0))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="0")
  inspect(wasi_errno_from_result(result.jit_result), content="0")
}

///|
test "wasi jit: fd_renumber allows stdio to preopen target (0)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_renumber"
    #|    (func $fd_renumber (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_renumber (i32.const 1) (i32.const 3))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="0")
  inspect(wasi_errno_from_result(result.jit_result), content="0")
}

///|
test "wasi jit: fd_renumber remaps stdio routing semantics" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_renumber"
    #|    (func $fd_renumber (param i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_read"
    #|    (func $fd_read (param i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_get"
    #|    (func $fd_fdstat_get (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (i32.store (i32.const 0) (i32.const 100))
    #|    (i32.store (i32.const 4) (i32.const 8))
    #|    (local.set $errno
    #|      (call $fd_renumber (i32.const 0) (i32.const 3)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (i32.const 100))))
    #|    (local.set $errno
    #|      (call $fd_read (i32.const 3) (i32.const 0) (i32.const 1) (i32.const 200)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (i32.const 101))))
    #|    (if (i32.ne (i32.load (i32.const 200)) (i32.const 0))
    #|      (then (return (i32.const 102))))
    #|    (local.set $errno
    #|      (call $fd_read (i32.const 0) (i32.const 0) (i32.const 1) (i32.const 204)))
    #|    (if (i32.ne (local.get $errno) (i32.const 8))
    #|      (then (return (i32.const 103))))
    #|    (local.set $errno
    #|      (call $fd_renumber (i32.const 1) (i32.const 3)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (i32.const 104))))
    #|    (local.set $errno
    #|      (call $fd_fdstat_get (i32.const 3) (i32.const 300)))
    #|    (if (i32.ne (local.get $errno) (i32.const 0))
    #|      (then (return (i32.const 105))))
    #|    (if (i64.ne (i64.load (i32.const 308)) (i64.const 64))
    #|      (then (return (i32.const 106))))
    #|    (local.set $errno
    #|      (call $fd_fdstat_get (i32.const 1) (i32.const 300)))
    #|    (if (i32.ne (local.get $errno) (i32.const 8))
    #|      (then (return (i32.const 107))))
    #|    (i32.const 0)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="0")
  inspect(wasi_errno_from_result(result.jit_result), content="0")
}

///|
test "wasi jit: fd_renumber rejects unused target with EBADF (8)" {
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
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="8")
  inspect(wasi_errno_from_result(result.jit_result), content="8")
}

///|
test "wasi jit: fd_fdstat_set_flags rejects DSYNC with EINVAL (28)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_set_flags"
    #|    (func $fd_fdstat_set_flags (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_setflags_file")
    #|  (func (export "test") (result i32)
    #|    (drop (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 20)
    #|      (i32.const 9) (i64.const 0) (i64.const 0) (i32.const 0)
    #|      (i32.const 100)))
    #|    (call $fd_fdstat_set_flags (i32.load (i32.const 100)) (i32.const 2))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="28")
  inspect(wasi_errno_from_result(result.jit_result), content="28")
}

///|
test "wasi jit: fd_fdstat_set_flags returns EBADF for non-file fd before DSYNC check" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_set_flags"
    #|    (func $fd_fdstat_set_flags (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (local $errno i32)
    #|    (local.set $errno
    #|      (call $fd_fdstat_set_flags (i32.const 0) (i32.const 2)))
    #|    (if (i32.ne (local.get $errno) (i32.const 8))
    #|      (then (return (i32.const 101))))
    #|    (call $fd_fdstat_set_flags (i32.const 3) (i32.const 2))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="8")
  inspect(wasi_errno_from_result(result.jit_result), content="8")
}

///|
test "wasi jit: fd_fdstat_set_flags traps on unknown bits" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_set_flags"
    #|    (func $fd_fdstat_set_flags (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_setflags_unknown")
    #|  (func (export "test") (result i32)
    #|    (drop (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 23)
    #|      (i32.const 9) (i64.const 0) (i64.const 0) (i32.const 0)
    #|      (i32.const 100)))
    #|    (call $fd_fdstat_set_flags (i32.load (i32.const 100)) (i32.const 32))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
}

///|
test "wasi jit: fd_fdstat_set_rights valid fd returns ENOTSUP (58)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_set_rights"
    #|    (func $fd_fdstat_set_rights (param i32 i64 i64) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_setrights_file")
    #|  (func (export "test") (result i32)
    #|    (drop (call $path_open
    #|      (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 21)
    #|      (i32.const 9) (i64.const 0) (i64.const 0) (i32.const 0)
    #|      (i32.const 100)))
    #|    (call $fd_fdstat_set_rights
    #|      (i32.load (i32.const 100))
    #|      (i64.const 0)
    #|      (i64.const 0))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="58")
  inspect(wasi_errno_from_result(result.jit_result), content="58")
}

///|
test "wasi jit: fd_fdstat_set_rights stdio returns EBADF (8)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_set_rights"
    #|    (func $fd_fdstat_set_rights (param i32 i64 i64) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_fdstat_set_rights (i32.const 0) (i64.const 0) (i64.const 0))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="8")
  inspect(wasi_errno_from_result(result.jit_result), content="8")
}

///|
test "wasi jit: fd_fdstat_set_rights preopen returns ENOTSUP (58)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_set_rights"
    #|    (func $fd_fdstat_set_rights (param i32 i64 i64) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_fdstat_set_rights (i32.const 3) (i64.const 0) (i64.const 0))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="58")
  inspect(wasi_errno_from_result(result.jit_result), content="58")
}

///|
test "wasi jit: fd_sync stdin returns EBADF (8)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_sync"
    #|    (func $fd_sync (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_sync (i32.const 0))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="8")
  inspect(wasi_errno_from_result(result.jit_result), content="8")
}

///|
test "wasi jit: fd_datasync stdout returns EBADF (8)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_datasync"
    #|    (func $fd_datasync (param i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $fd_datasync (i32.const 1))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="8")
  inspect(wasi_errno_from_result(result.jit_result), content="8")
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
test "wasi jit: fd_fdstat_get stdin rights match interpreter" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_get"
    #|    (func $fd_fdstat_get (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i64)
    #|    (drop (call $fd_fdstat_get (i32.const 0) (i32.const 0)))
    #|    (i64.load (i32.const 8))))
  inspect(compare_wasi(source, "test"), content="matched")
}

///|
test "wasi jit: fd_fdstat_get preopen base rights match interpreter" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_get"
    #|    (func $fd_fdstat_get (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i64)
    #|    (drop (call $fd_fdstat_get (i32.const 3) (i32.const 0)))
    #|    (i64.load (i32.const 8))))
  inspect(
    compare_wasi_with_options(source, "test", preopens=[("/tmp", "/")]),
    content="matched",
  )
}

///|
test "wasi jit: fd_fdstat_get preopen inheriting rights match interpreter" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_get"
    #|    (func $fd_fdstat_get (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i64)
    #|    (drop (call $fd_fdstat_get (i32.const 3) (i32.const 0)))
    #|    (i64.load (i32.const 16))))
  inspect(
    compare_wasi_with_options(source, "test", preopens=[("/tmp", "/")]),
    content="matched",
  )
}

///|
test "wasi jit: sock_accept on valid descriptor returns ENOTSOCK (57)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "sock_accept"
    #|    (func $sock_accept (param i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $sock_accept (i32.const 0) (i32.const 0) (i32.const 0))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="57")
  inspect(wasi_errno_from_result(result.jit_result), content="57")
}

///|
test "wasi jit: sock_recv on valid descriptor returns ENOTSOCK (57)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "sock_recv"
    #|    (func $sock_recv (param i32 i32 i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $sock_recv (i32.const 0) (i32.const 0) (i32.const 0) (i32.const 0) (i32.const 0) (i32.const 0))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="57")
  inspect(wasi_errno_from_result(result.jit_result), content="57")
}

///|
test "wasi jit: sock_send on valid descriptor returns ENOTSOCK (57)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "sock_send"
    #|    (func $sock_send (param i32 i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $sock_send (i32.const 0) (i32.const 0) (i32.const 0) (i32.const 0) (i32.const 0))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="57")
  inspect(wasi_errno_from_result(result.jit_result), content="57")
}

///|
test "wasi jit: sock_shutdown on valid descriptor returns ENOTSOCK (57)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "sock_shutdown"
    #|    (func $sock_shutdown (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $sock_shutdown (i32.const 0) (i32.const 0))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="57")
  inspect(wasi_errno_from_result(result.jit_result), content="57")
}

///|
test "wasi jit: sock_accept traps on unknown fdflags bits" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "sock_accept"
    #|    (func $sock_accept (param i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $sock_accept (i32.const 0) (i32.const 0x20) (i32.const 0))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
}

///|
test "wasi jit: sock_recv traps on unknown riflags bits" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "sock_recv"
    #|    (func $sock_recv (param i32 i32 i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "\20\00\00\00\04\00\00\00")
    #|  (func (export "test") (result i32)
    #|    (call $sock_recv (i32.const 0) (i32.const 0) (i32.const 1) (i32.const 0x04) (i32.const 16) (i32.const 20))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
}

///|
test "wasi jit: sock_shutdown traps on unknown sdflags bits" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "sock_shutdown"
    #|    (func $sock_shutdown (param i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (call $sock_shutdown (i32.const 0) (i32.const 0x04))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="-1")
  inspect(wasi_errno_from_result(result.jit_result), content="-1")
}

///|
test "wasi jit: sock_send nonzero siflags still returns ENOTSOCK (57)" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "sock_send"
    #|    (func $sock_send (param i32 i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "\20\00\00\00\04\00\00\00")
    #|  (func (export "test") (result i32)
    #|    (call $sock_send (i32.const 0) (i32.const 0) (i32.const 1) (i32.const 1) (i32.const 16))))
  let result = compare_wasi(source, "test")
  inspect(result.match_, content="true")
  inspect(wasi_errno_from_result(result.interp_result), content="57")
  inspect(wasi_errno_from_result(result.jit_result), content="57")
}
