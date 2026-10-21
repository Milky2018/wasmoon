///|
/// DWARF Debug Info Builder
///
/// This module provides a high-level interface for generating DWARF debug
/// information and registering JIT code with debuggers like LLDB.
///
/// Usage:
///   let dwarf = DWARFBuilder::DWARFBuilder()
///   dwarf.add_function("func_0", addr, size, 0)
///   dwarf.add_function("func_1", addr, size, 1)
///   dwarf.register()  // Register with LLDB
///   // ... JIT code runs here ...
///   dwarf.destroy()   // Optional early cleanup; otherwise RC runs the finalizer

///|
/// DWARF debug info builder
/// Owns native metadata and debugger registration through MoonBit RC.
/// All aliases share the same state; destroy closes them together.
pub type DWARFBuilder

///|
/// Create a new DWARF builder
pub fn DWARFBuilder::DWARFBuilder() -> DWARFBuilder {
  c_dwarf_create()
}

///|
/// Add a function to the DWARF debug info
/// Parameters:
///   name: Function name (e.g., "func_42" or "my_function")
///   addr: Function start address in memory
///   size: Function size in bytes
///   func_idx: WebAssembly function index
pub fn DWARFBuilder::add_function(
  self : DWARFBuilder,
  name : String,
  addr : Int64,
  size : Int32,
  func_idx : Int32,
) -> Unit {
  // Convert string to null-terminated bytes
  let bytes = @utf8.encode(name).to_array()
  bytes.push(0)
  let name_bytes = Bytes::from_array(bytes)
  c_dwarf_add_function(self, name_bytes, addr, size, func_idx)
}

///|
/// Register the DWARF debug info with the debugger
/// This generates an in-memory Mach-O/ELF object file with DWARF sections
/// and registers it with LLDB/GDB via the standard JIT interface.
/// After calling this, function names will appear in stack traces.
/// Also sets this builder as the active one for backtrace lookups.
/// Returns false on an empty/closed builder, exceeded function capacity, or native allocation failure.
/// verbose: if true, print debug info to stderr
pub fn DWARFBuilder::register(
  self : DWARFBuilder,
  verbose~ : Bool = false,
) -> Bool {
  guard c_dwarf_register(self, if verbose { 1 } else { 0 }) else {
    return false
  }
  // Set as active for backtrace lookups
  c_dwarf_set_active(self)
  true
}

///|
/// Unregister DWARF debug info from the debugger
/// Call this before destroying if you want to explicitly unregister
pub fn DWARFBuilder::unregister(self : DWARFBuilder) -> Unit {
  c_dwarf_unregister(self)
}

///|
/// Destroy the DWARF builder and free all resources
/// This also unregisters debug info. Repeated calls are harmless.
/// Closed builders ignore mutations and return None from address lookup.
pub fn DWARFBuilder::destroy(self : DWARFBuilder) -> Unit {
  c_dwarf_destroy(self)
}

///|
/// Function lookup result
pub struct FunctionInfo {
  name : String
  func_idx : Int32
  offset : Int64
}

///|
/// Lookup an address to find which function it belongs to
/// Returns None if the address is not in any known function
pub fn DWARFBuilder::lookup_address(
  self : DWARFBuilder,
  addr : Int64,
) -> FunctionInfo? {
  let func_idx_buf = FixedArray::make(1, 0)
  let offset_buf = FixedArray::make(1, 0L)
  // The native owner reports the complete UTF-8 size, including its terminator.
  let required = c_dwarf_lookup_address(
    self,
    addr,
    FixedArray::make(0, b'\x00'),
    0,
    func_idx_buf,
    offset_buf,
  )
  guard required > 0 else { return None }
  let name_buf = FixedArray::make(required, b'\x00')
  guard c_dwarf_lookup_address(
      self, addr, name_buf, required, func_idx_buf, offset_buf,
    ) ==
    required else {
    return None
  }
  let bytes = Bytes::from_array(Array::makei(required - 1, i => name_buf[i]))
  let name = @utf8.decode_lossy(bytes[:])
  Some({ name, func_idx: func_idx_buf[0], offset: offset_buf[0], })
}

///|
/// Backtrace frame
pub struct BacktraceFrame {
  pc : Int64
  name : String
  offset : Int64
  func_idx : Int32
}

///|
/// Capture and format a backtrace from the current trap state
/// Returns an array of backtrace frames
pub fn DWARFBuilder::capture_backtrace(
  self : DWARFBuilder,
) -> Array[BacktraceFrame] {
  let pc = c_jit_get_trap_pc()
  let fp = c_jit_get_trap_fp()
  let lr = c_jit_get_trap_lr()
  if pc == 0L {
    return []
  }
  // Capture up to 32 frames
  // Use the extended function that includes LR for when FP is 0
  let max_frames = 32
  let frames_buf = FixedArray::make(max_frames * 2, 0L)
  let frame_count = c_dwarf_capture_backtrace_ex(
    pc, fp, lr, frames_buf, max_frames,
  )
  // Convert to BacktraceFrame array
  let result : Array[BacktraceFrame] = []
  for i in 0..<frame_count {
    let frame_pc = frames_buf[i * 2]
    match self.lookup_address(frame_pc) {
      Some(info) =>
        result.push({
          pc: frame_pc,
          name: info.name,
          offset: info.offset,
          func_idx: info.func_idx,
        })
      None =>
        result.push({
          pc: frame_pc,
          name: "<unknown>",
          offset: 0L,
          func_idx: -1,
        })
    }
  }
  result
}

///|
/// Format a backtrace as a string
pub fn DWARFBuilder::format_backtrace(
  _self : DWARFBuilder,
  frames : Array[BacktraceFrame],
) -> String {
  let sb = StringBuilder::StringBuilder()
  for i, frame in frames {
    if frame.func_idx >= 0 {
      sb.write_string("  #\{i} 0x")
      sb.write_string(format_hex(frame.pc))
      sb.write_string(" \{frame.name}+0x")
      sb.write_string(format_hex(frame.offset))
      sb.write_string("\n")
    } else {
      sb.write_string("  #\{i} 0x")
      sb.write_string(format_hex(frame.pc))
      sb.write_string(" <unknown>\n")
    }
  }
  sb.to_string()
}

///|
/// Format an Int64 as hexadecimal string
fn format_hex(n : Int64) -> String {
  if n == 0L {
    return "0"
  }
  let hex_chars = "0123456789abcdef"
  let mut result = ""
  let mut value = n.reinterpret_as_uint64()
  while value > 0UL {
    let digit = (value & 0xFUL).to_int()
    result = hex_chars.code_unit_at(digit).unsafe_to_char().to_string() + result
    value = value >> 4
  }
  result
}
