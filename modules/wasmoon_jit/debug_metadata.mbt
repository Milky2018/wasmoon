/// Debug metadata captured while compiling a JIT module.

///|
/// A resolved wasm frame in a native trap report.
pub(all) struct WasmTrapFrame {
  pc : Int64
  func_idx : Int
  func_name : String
  wasm_offset : Int64
}

///|
/// Structured trap report for native integrations.
pub(all) struct TrapReport {
  trap_kind : String
  message : String
  signal : Int
  signal_name : String
  pc : Int64
  lr : Int64
  fp : Int64
  frame_lr : Int64
  fault_addr : Int64
  brk_imm : Int
  wasm_func_idx : Int?
  wasm_func_name : String?
  wasm_offset : Int64?
  wasm_frames : Array[WasmTrapFrame]
  host_frames : Array[String]
  dump_path : String?
}

///|
/// Per-function compilation dumps captured for dump-on-trap.
pub struct JITFunctionDebug {
  ir : String
  vcode_before_regalloc : String
  vcode_after_regalloc : String
  machine_code : String
}

///|
pub fn JITFunctionDebug::new(
  ir : String,
  vcode_before_regalloc : String,
  vcode_after_regalloc : String,
  machine_code : String,
) -> JITFunctionDebug {
  { ir, vcode_before_regalloc, vcode_after_regalloc, machine_code }
}

///|
/// Optional in-memory database of per-function debug dumps.
pub struct JITDebugDB {
  entries : Map[Int, JITFunctionDebug]
}

///|
pub fn JITDebugDB::new() -> JITDebugDB {
  { entries: Map([]) }
}

///|
pub fn JITDebugDB::set(
  self : JITDebugDB,
  func_idx : Int,
  debug : JITFunctionDebug,
) -> Unit {
  self.entries.set(func_idx, debug)
}

///|
pub fn JITDebugDB::get(self : JITDebugDB, func_idx : Int) -> JITFunctionDebug? {
  self.entries.get(func_idx)
}
