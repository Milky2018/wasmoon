/// Wasmoon-owned native JIT trap and value-slot primitives.

/// Wasmoon-owned native JIT runtime primitives and managed handles.

///|
/// Read an i64-sized slot from a JIT-owned native value area.
pub fn native_value_slot_read(base : Int64, slot : Int) -> Int64 {
  c_jit_read_i64(base + (slot * 8).to_int64())
}

///|
/// Write an i64-sized slot in a JIT-owned native value area.
pub fn native_value_slot_write(base : Int64, slot : Int, value : Int64) -> Unit {
  c_jit_write_i64(base + (slot * 8).to_int64(), value)
}

///|
/// Low-level trap detail captured by the JIT signal handlers (best-effort).
pub struct TrapDetails {
  signal : Int
  pc : Int64
  lr : Int64
  fp : Int64
  frame_lr : Int64
  fault_addr : Int64
  brk_imm : Int
  func_idx : Int
  x0 : Int64
  x1 : Int64
  x2 : Int64
  x3 : Int64
  x6 : Int64
  x7 : Int64
  x8 : Int64
  x9 : Int64
  x10 : Int64
  x11 : Int64
  x15 : Int64
}

///|
pub fn TrapDetails::TrapDetails() -> TrapDetails {
  {
    signal: 0,
    pc: 0L,
    lr: 0L,
    fp: 0L,
    frame_lr: 0L,
    fault_addr: 0L,
    brk_imm: 0,
    func_idx: -1,
    x0: 0L,
    x1: 0L,
    x2: 0L,
    x3: 0L,
    x6: 0L,
    x7: 0L,
    x8: 0L,
    x9: 0L,
    x10: 0L,
    x11: 0L,
    x15: 0L,
  }
}

///|
/// Get the last captured trap details (best-effort).
/// These fields are reset at the start of each JIT call.
pub fn get_last_trap_details() -> TrapDetails {
  {
    signal: c_jit_get_trap_signal(),
    pc: c_jit_get_trap_pc(),
    lr: c_jit_get_trap_lr(),
    fp: c_jit_get_trap_fp(),
    frame_lr: c_jit_get_trap_frame_lr(),
    fault_addr: c_jit_get_trap_fault_addr(),
    brk_imm: c_jit_get_trap_brk_imm(),
    func_idx: c_jit_get_trap_func_idx(),
    x0: c_jit_get_trap_xreg(0),
    x1: c_jit_get_trap_xreg(1),
    x2: c_jit_get_trap_xreg(2),
    x3: c_jit_get_trap_xreg(3),
    x6: c_jit_get_trap_xreg(6),
    x7: c_jit_get_trap_xreg(7),
    x8: c_jit_get_trap_xreg(8),
    x9: c_jit_get_trap_xreg(9),
    x10: c_jit_get_trap_xreg(10),
    x11: c_jit_get_trap_xreg(11),
    x15: c_jit_get_trap_xreg(15),
  }
}

///|
pub fn format_signal_name(sig : Int) -> String {
  match sig {
    5 => "SIGTRAP(5)"
    10 => "SIGBUS(10)"
    11 => "SIGSEGV(11)"
    7 => "SIGBUS(7)"
    _ => "SIG(\{sig})"
  }
}

///|
pub fn jit_trap_message(code : Int) -> String {
  match code {
    1 => "out of bounds memory access"
    2 => "call stack exhausted"
    3 => "unreachable"
    4 => "indirect call type mismatch"
    5 => "invalid conversion to integer"
    6 => "integer divide by zero"
    7 => "integer overflow"
    8 => "jit backend trap"
    9 => "out of memory"
    10 => "gc precise roots unavailable"
    11 => "invocation cancelled"
    _ => "unknown trap"
  }
}

///|
pub fn is_cancelled_trap_code(code : Int) -> Bool {
  code == 11
}

///|
/// Map Wasm trap reasons to the payload consumed by Wasmoon's native trap
/// handler. MachV only carries the integer payload; this module owns the
/// Wasmoon-specific reason-to-payload policy.
pub fn wasm_trap_payload(reason : String) -> Int {
  if reason == "unreachable" {
    0
  } else if reason.contains("out of bounds") {
    1
  } else if reason.contains("type mismatch") {
    2
  } else if reason.contains("invalid conversion") {
    3
  } else if reason.contains("divide by zero") {
    4
  } else if reason.contains("overflow") {
    5
  } else {
    6
  }
}

///|
pub fn take_pending_trap_message() -> String? {
  let code = c_jit_get_trap_code()
  if code == 0 {
    None
  } else {
    c_jit_clear_trap()
    Some(jit_trap_message(code))
  }
}

///|
pub fn is_wasi_exit_trap_code(code : Int) -> Bool {
  code == 100
}
