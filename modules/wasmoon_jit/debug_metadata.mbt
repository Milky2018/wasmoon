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
  machv_before_regalloc : String
  machv_after_regalloc : String
  machine_code : String
}

///|
pub fn JITFunctionDebug::JITFunctionDebug(
  ir : String,
  machv_before_regalloc : String,
  machv_after_regalloc : String,
  machine_code : String,
) -> JITFunctionDebug {
  { ir, machv_before_regalloc, machv_after_regalloc, machine_code }
}

///|
/// Optional in-memory database of per-function debug dumps.
pub struct JITDebugDB {
  entries : Map[Int, JITFunctionDebug]
}

///|
pub fn JITDebugDB::JITDebugDB() -> JITDebugDB {
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

///|
pub fn format_u64_hex(v : Int64) -> String {
  let u = v.reinterpret_as_uint64()
  let b7 = (u >> 56).reinterpret_as_int64().to_int() & 0xFF
  let b6 = (u >> 48).reinterpret_as_int64().to_int() & 0xFF
  let b5 = (u >> 40).reinterpret_as_int64().to_int() & 0xFF
  let b4 = (u >> 32).reinterpret_as_int64().to_int() & 0xFF
  let b3 = (u >> 24).reinterpret_as_int64().to_int() & 0xFF
  let b2 = (u >> 16).reinterpret_as_int64().to_int() & 0xFF
  let b1 = (u >> 8).reinterpret_as_int64().to_int() & 0xFF
  let b0 = u.reinterpret_as_int64().to_int() & 0xFF
  "0x" +
  @types.to_hex_byte(b7) +
  @types.to_hex_byte(b6) +
  @types.to_hex_byte(b5) +
  @types.to_hex_byte(b4) +
  @types.to_hex_byte(b3) +
  @types.to_hex_byte(b2) +
  @types.to_hex_byte(b1) +
  @types.to_hex_byte(b0)
}

///|
pub fn sanitize_debug_filename(s : String) -> String {
  let mut out = ""
  for c in s {
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-' ||
      c == '.'
    out = out + (if ok { c.to_string() } else { "_" })
  }
  if out.is_empty() {
    "unknown"
  } else {
    out
  }
}

///|
pub fn format_trap_report_message(report : TrapReport) -> String {
  let fields : Array[String] = []
  if report.signal != 0 {
    fields.push("sig=\{report.signal_name}")
  }
  if report.pc != 0L {
    fields.push("pc=\{format_u64_hex(report.pc)}")
  }
  if report.lr != 0L {
    fields.push("lr=\{format_u64_hex(report.lr)}")
  }
  if report.frame_lr != 0L {
    fields.push("frame_lr=\{format_u64_hex(report.frame_lr)}")
  }
  if report.fault_addr != 0L {
    fields.push("addr=\{format_u64_hex(report.fault_addr)}")
  }
  if report.brk_imm >= 0 {
    fields.push("brk_imm=\{report.brk_imm}")
  }
  if report.wasm_func_idx is Some(func_idx) {
    match (report.wasm_func_name, report.wasm_offset) {
      (Some(name), Some(offset)) =>
        fields.push(
          "wasm=\{func_idx} '\{name}'+0x\{@types.int_to_hex(offset.to_int())}",
        )
      (Some(name), None) => fields.push("wasm=\{func_idx} '\{name}'")
      (None, Some(offset)) =>
        fields.push("wasm=\{func_idx} +0x\{@types.int_to_hex(offset.to_int())}")
      (None, None) => fields.push("wasm=\{func_idx}")
    }
  }
  if report.wasm_frames.length() > 1 {
    let caller = report.wasm_frames[1]
    fields.push(
      "caller=\{caller.func_idx} '\{caller.func_name}'+0x\{@types.int_to_hex(caller.wasm_offset.to_int())}",
    )
  }
  if report.dump_path is Some(path) {
    fields.push("dump=\{path}")
  }
  if fields.is_empty() {
    report.message
  } else {
    report.message + " (" + fields.join(", ") + ")"
  }
}
