///|
/// Backtrace tests for JIT traps
/// These tests verify that the backtrace capture correctly unwinds the stack

///|
/// Helper struct to capture trap info with backtrace
struct TrapInfo {
  trap_msg : String
  backtrace : Array[@jit.BacktraceFrame]
  // Raw values for debugging
  trap_details : @jit.TrapDetails
}

///|
/// Run JIT with DWARF enabled and capture backtrace on trap
fn run_jit_with_backtrace(
  source : String,
  func_name : String,
  args : Array[@types.Value],
) -> Result[Array[@types.Value], TrapInfo] {
  let mod_ = @wat.parse(source) catch {
    e => return Err(make_empty_trap_info("Failed to parse WAT: \{e}"))
  }

  // Find the function index by name
  let func_idx = find_func_index_by_name(mod_, func_name)
  guard func_idx is Some(idx) else {
    return Err(make_empty_trap_info("Function '\{func_name}' not found"))
  }
  let num_imports = @wast.count_func_imports(mod_.imports)
  let local_idx = idx - num_imports
  guard local_idx >= 0 && local_idx < mod_.funcs.length() else {
    return Err(
      make_empty_trap_info(
        "Function '\{func_name}' is not a local function (func_idx=\{idx}, func_imports=\{num_imports})",
      ),
    )
  }

  // Get function type
  let func_type_idx = mod_.funcs[local_idx]
  let func_type = mod_.get_func_type(func_type_idx)
  let param_types = func_type.params
  let result_types = func_type.results

  // Compile with DWARF enabled
  let precompiled = @cwasm.PrecompiledModule::new(@cwasm.AArch64)

  // Compile each function in the module
  for i, _ in mod_.codes {
    let f_idx = num_imports + i
    let type_idx = mod_.funcs[i]
    let func_type_inner = mod_.get_func_type(type_idx)
    let f_name = @wast.get_func_name(mod_, f_idx)
    let ir_func = @ir.translate_function(mod_, i, name=f_name)
    let vcode = @lower.lower_function(ir_func)
    let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
    let mc = @emit.emit_function(allocated_func, force_frame_setup=true)
    let compiled = @vcode.CompiledFunction::new(f_name, mc, 0)
    precompiled.add_function(
      f_idx,
      f_name,
      compiled,
      func_type_inner.params.length(),
      func_type_inner.results.length(),
    )
  }

  // Build func_signatures for JIT module
  let func_signatures = @wast.build_func_signatures(mod_)

  // Load JIT module
  guard @jit.JITModule::load(precompiled, func_signatures) is Some(jm) else {
    return Err(make_empty_trap_info("Failed to create JIT module"))
  }

  // Register DWARF info - this is the key for backtraces!
  let dwarf = jm.register_dwarf()

  // Allocate WASM stack
  jm.alloc_wasm_stack(1048576L) |> ignore

  // Initialize tables if present
  init_elem_segments(mod_, jm, [])

  // Prepare arguments
  let i64_args : Array[Int64] = []
  for i, arg in args {
    let expected_type = param_types[i]
    match (expected_type, arg) {
      (I32, I32(v)) => i64_args.push(v.to_int64())
      (I64, I64(v)) => i64_args.push(v)
      (F32, F32(v)) => i64_args.push(v.reinterpret_as_int().to_int64())
      (F64, F64(v)) => i64_args.push(v.reinterpret_as_int64())
      _ => i64_args.push(0L)
    }
  }

  // Find function and call it
  guard jm.get_func_by_name(func_name) is Some(f) else {
    return Err(make_empty_trap_info("Function not found in JIT module"))
  }

  // Call and handle trap
  let results = jm.call_with_context(f, i64_args) catch {
    @jit.JITExit(code) => {
      let frames = dwarf.capture_backtrace()
      let trap_details = @jit.get_last_trap_details()
      return Err({
        trap_msg: "WASI exit: \{code}",
        backtrace: frames,
        trap_details,
      })
    }
    @jit.JITTrap(msg) => {
      let frames = dwarf.capture_backtrace()
      let trap_details = @jit.get_last_trap_details()
      return Err({ trap_msg: msg, backtrace: frames, trap_details })
    }
  }

  // Convert results
  let output : Array[@types.Value] = []
  for i, r in results {
    let typ = result_types[i]
    match typ {
      I32 => output.push(I32(r.to_int()))
      I64 => output.push(I64(r))
      F32 => output.push(F32(Float::reinterpret_from_int(r.to_int())))
      F64 => output.push(F64(r.reinterpret_as_double()))
      _ => output.push(I32(0))
    }
  }
  Ok(output)
}

///|
/// Helper to create an empty TrapInfo for error cases
fn make_empty_trap_info(msg : String) -> TrapInfo {
  { trap_msg: msg, backtrace: [], trap_details: @jit.TrapDetails::new() }
}

///|
/// Format backtrace for snapshot - normalize addresses for reproducibility
fn format_backtrace_for_snapshot(info : TrapInfo) -> String {
  let sb = StringBuilder::new()
  // Extract just the trap type (before addresses)
  let trap_type = extract_trap_type(info.trap_msg)
  sb.write_string("trap_type: \{trap_type}\n")
  sb.write_string("frames: \{info.backtrace.length()}\n")
  for i, frame in info.backtrace {
    // Don't include actual addresses, just function names
    if frame.func_idx >= 0 {
      sb.write_string("  #\{i} \{frame.name} (func_idx=\{frame.func_idx})\n")
    } else {
      sb.write_string("  #\{i} <unknown>\n")
    }
  }
  // Debug info - show if fp/lr are captured (nonzero or not)
  let d = info.trap_details
  sb.write_string("debug: fp=")
  sb.write_string(if d.fp == 0L { "0" } else { "nonzero" })
  sb.write_string(", lr=")
  sb.write_string(if d.lr == 0L { "0" } else { "nonzero" })
  sb.write_string(", frame_lr=")
  sb.write_string(if d.frame_lr == 0L { "0" } else { "nonzero" })
  sb.to_string()
}

///|
/// Extract trap type from message (e.g., "unreachable" from "unreachable (sig=...)")
fn extract_trap_type(msg : String) -> String {
  for i, c in msg {
    if c == ' ' || c == '(' {
      return try! msg[0:i].to_string()
    }
  }
  msg
}

///|
/// Helper to find function index by name
fn find_func_index_by_name(mod_ : @types.Module, name : String) -> Int? {
  for exp in mod_.exports {
    if exp.name == name && exp.desc is @types.ExportDesc::Func(idx) {
      return Some(idx)
    }
  }
  None
}

// ============================================================================
// Test Cases
// ============================================================================

///|
test "backtrace: simple unreachable" {
  let source =
    #|(module
    #|  (func (export "test")
    #|    unreachable)
    #|)
  let result = run_jit_with_backtrace(source, "test", [])
  guard result is Err(info) else { return fail("Expected trap, got success") }
  inspect(
    format_backtrace_for_snapshot(info),
    content=(
      #|trap_type: unreachable
      #|frames: 1
      #|  #0 test (func_idx=0)
      #|debug: fp=nonzero, lr=nonzero, frame_lr=nonzero
    ),
  )
}

///|
test "backtrace: unreachable after some ops" {
  let source =
    #|(module
    #|  (func (export "test") (param i32) (result i32)
    #|    (local.get 0)
    #|    (i32.const 1)
    #|    (i32.add)
    #|    (drop)
    #|    unreachable)
    #|)
  let result = run_jit_with_backtrace(source, "test", [I32(42)])
  guard result is Err(info) else { return fail("Expected trap, got success") }
  inspect(
    format_backtrace_for_snapshot(info),
    content=(
      #|trap_type: unreachable
      #|frames: 1
      #|  #0 test (func_idx=0)
      #|debug: fp=nonzero, lr=nonzero, frame_lr=nonzero
    ),
  )
}

///|
test "backtrace: two-level call - callee traps" {
  let source =
    #|(module
    #|  (func $inner
    #|    unreachable)
    #|  (func (export "test")
    #|    (call $inner))
    #|)
  let result = run_jit_with_backtrace(source, "test", [])
  guard result is Err(info) else { return fail("Expected trap, got success") }
  inspect(
    format_backtrace_for_snapshot(info),
    content=(
      #|trap_type: unreachable
      #|frames: 2
      #|  #0 func_0 (func_idx=0)
      #|  #1 test (func_idx=1)
      #|debug: fp=nonzero, lr=nonzero, frame_lr=nonzero
    ),
  )
}

///|
test "backtrace: three-level call - deepest traps" {
  let source =
    #|(module
    #|  (func $deep
    #|    unreachable)
    #|  (func $middle
    #|    (call $deep))
    #|  (func (export "test")
    #|    (call $middle))
    #|)
  let result = run_jit_with_backtrace(source, "test", [])
  guard result is Err(info) else { return fail("Expected trap, got success") }
  inspect(
    format_backtrace_for_snapshot(info),
    content=(
      #|trap_type: unreachable
      #|frames: 3
      #|  #0 func_0 (func_idx=0)
      #|  #1 func_1 (func_idx=1)
      #|  #2 test (func_idx=2)
      #|debug: fp=nonzero, lr=nonzero, frame_lr=nonzero
    ),
  )
}

///|
test "backtrace: recursive call" {
  let source =
    #|(module
    #|  (func $recurse (param i32)
    #|    (if (i32.gt_s (local.get 0) (i32.const 0))
    #|      (then (call $recurse (i32.sub (local.get 0) (i32.const 1))))
    #|      (else unreachable)))
    #|  (func (export "test")
    #|    (call $recurse (i32.const 3)))
    #|)
  let result = run_jit_with_backtrace(source, "test", [])
  guard result is Err(info) else { return fail("Expected trap, got success") }
  inspect(
    format_backtrace_for_snapshot(info),
    content=(
      #|trap_type: unreachable
      #|frames: 5
      #|  #0 func_0 (func_idx=0)
      #|  #1 func_0 (func_idx=0)
      #|  #2 func_0 (func_idx=0)
      #|  #3 func_0 (func_idx=0)
      #|  #4 test (func_idx=1)
      #|debug: fp=nonzero, lr=nonzero, frame_lr=nonzero
    ),
  )
}

///|
test "backtrace: call_indirect trap" {
  let source =
    #|(module
    #|  (table 1 funcref)
    #|  (func $f (result i32) (i32.const 42))
    #|  (elem (i32.const 0) $f)
    #|  (type $sig (func (result i32)))
    #|  (func (export "test") (result i32)
    #|    ;; Call index 1, which is out of bounds (table has only 1 element)
    #|    (call_indirect (type $sig) (i32.const 1)))
    #|)
  let result = run_jit_with_backtrace(source, "test", [])
  guard result is Err(info) else { return fail("Expected trap, got success") }
  inspect(
    format_backtrace_for_snapshot(info),
    content=(
      #|trap_type: unreachable
      #|frames: 1
      #|  #0 test (func_idx=1)
      #|debug: fp=nonzero, lr=nonzero, frame_lr=nonzero
    ),
  )
}

///|
test "backtrace: out of bounds memory access" {
  let source =
    #|(module
    #|  (memory 1) ;; 1 page = 64KB
    #|  (func (export "test") (result i32)
    #|    ;; Access beyond memory bounds
    #|    (i32.load (i32.const 65536)))
    #|)
  let result = run_jit_with_backtrace(source, "test", [])
  guard result is Err(info) else { return fail("Expected trap, got success") }
  inspect(
    format_backtrace_for_snapshot(info),
    content=(
      #|trap_type: unknown
      #|frames: 1
      #|  #0 test (func_idx=0)
      #|debug: fp=nonzero, lr=nonzero, frame_lr=nonzero
    ),
  )
}

///|
test "backtrace: divide by zero" {
  let source =
    #|(module
    #|  (func (export "test") (param i32) (result i32)
    #|    (i32.div_s (local.get 0) (i32.const 0)))
    #|)
  let result = run_jit_with_backtrace(source, "test", [I32(42)])
  guard result is Err(info) else { return fail("Expected trap, got success") }
  inspect(
    format_backtrace_for_snapshot(info),
    content=(
      #|trap_type: integer
      #|frames: 1
      #|  #0 test (func_idx=0)
      #|debug: fp=nonzero, lr=nonzero, frame_lr=nonzero
    ),
  )
}

///|
test "backtrace: call chain with args" {
  let source =
    #|(module
    #|  (func $add_and_trap (param i32 i32)
    #|    (drop (i32.add (local.get 0) (local.get 1)))
    #|    unreachable)
    #|  (func $caller (param i32)
    #|    (call $add_and_trap (local.get 0) (i32.const 10)))
    #|  (func (export "test")
    #|    (call $caller (i32.const 5)))
    #|)
  let result = run_jit_with_backtrace(source, "test", [])
  guard result is Err(info) else { return fail("Expected trap, got success") }
  inspect(
    format_backtrace_for_snapshot(info),
    content=(
      #|trap_type: unreachable
      #|frames: 3
      #|  #0 func_0 (func_idx=0)
      #|  #1 func_1 (func_idx=1)
      #|  #2 test (func_idx=2)
      #|debug: fp=nonzero, lr=nonzero, frame_lr=nonzero
    ),
  )
}

///|
test "backtrace: trap in conditional branch" {
  let source =
    #|(module
    #|  (func (export "test") (param i32)
    #|    (if (i32.eqz (local.get 0))
    #|      (then unreachable)
    #|      (else nop)))
    #|)
  let result = run_jit_with_backtrace(source, "test", [I32(0)])
  guard result is Err(info) else { return fail("Expected trap, got success") }
  inspect(
    format_backtrace_for_snapshot(info),
    content=(
      #|trap_type: unreachable
      #|frames: 1
      #|  #0 test (func_idx=0)
      #|debug: fp=nonzero, lr=nonzero, frame_lr=nonzero
    ),
  )
}
