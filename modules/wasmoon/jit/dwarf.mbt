///|
/// DWARF Debug Info Builder
///
/// This module provides a high-level interface for generating DWARF debug
/// information and registering JIT code with debuggers like LLDB.
///
/// Usage:
///   let dwarf = DWARFBuilder::new()
///   dwarf.add_function("func_0", addr, size, 0)
///   dwarf.add_function("func_1", addr, size, 1)
///   dwarf.register()  // Register with LLDB
///   // ... JIT code runs here ...
///   dwarf.destroy()   // Cleanup when done

///|
/// DWARF debug info builder
/// Accumulates function metadata and generates DWARF sections
pub struct DWARFBuilder {
  priv handle : Int64
}

///|
/// Create a new DWARF builder
pub fn DWARFBuilder::new() -> DWARFBuilder {
  { handle: @jit_ffi.c_dwarf_create() }
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
  size : Int,
  func_idx : Int,
) -> Unit {
  // Convert string to null-terminated bytes
  let name_bytes = Bytes::from_array(
    name.to_array().map(fn(c) { c.to_int().to_byte() }),
  )
  @jit_ffi.c_dwarf_add_function(self.handle, name_bytes, addr, size, func_idx)
}

///|
/// Register the DWARF debug info with the debugger
/// This generates an in-memory Mach-O/ELF object file with DWARF sections
/// and registers it with LLDB/GDB via the standard JIT interface.
/// After calling this, function names will appear in stack traces.
/// Also sets this builder as the active one for backtrace lookups.
/// verbose: if true, print debug info to stderr
pub fn DWARFBuilder::register(
  self : DWARFBuilder,
  verbose? : Bool = false,
) -> Unit {
  @jit_ffi.c_dwarf_register(self.handle, if verbose { 1 } else { 0 })
  // Set as active for backtrace lookups
  @jit_ffi.c_dwarf_set_active(self.handle)
}

///|
/// Unregister DWARF debug info from the debugger
/// Call this before destroying if you want to explicitly unregister
pub fn DWARFBuilder::unregister(self : DWARFBuilder) -> Unit {
  @jit_ffi.c_dwarf_unregister(self.handle)
}

///|
/// Destroy the DWARF builder and free all resources
/// This also unregisters the debug info if it was registered
pub fn DWARFBuilder::destroy(self : DWARFBuilder) -> Unit {
  @jit_ffi.c_dwarf_destroy(self.handle)
}

///|
/// Function lookup result
pub struct FunctionInfo {
  name : String
  func_idx : Int
  offset : Int64
}

///|
/// Lookup an address to find which function it belongs to
/// Returns None if the address is not in any known function
pub fn DWARFBuilder::lookup_address(
  self : DWARFBuilder,
  addr : Int64,
) -> FunctionInfo? {
  let name_buf = FixedArray::make(256, b'\x00')
  let func_idx_buf = FixedArray::make(1, 0)
  let offset_buf = FixedArray::make(1, 0L)
  let found = @jit_ffi.c_dwarf_lookup_address(
    self.handle,
    addr,
    name_buf,
    256,
    func_idx_buf,
    offset_buf,
  )
  if found != 0 {
    // Convert null-terminated bytes to string
    let mut name_len = 0
    for i in 0..<256 {
      if name_buf[i] == b'\x00' {
        name_len = i
        break
      }
    }
    let name = String::from_array(
      FixedArray::makei(name_len, fn(i) {
        name_buf[i].to_int().unsafe_to_char()
      }),
    )
    Some({ name, func_idx: func_idx_buf[0], offset: offset_buf[0] })
  } else {
    None
  }
}

///|
/// Backtrace frame
pub struct BacktraceFrame {
  pc : Int64
  name : String
  offset : Int64
  func_idx : Int
}

///|
/// Capture and format a backtrace from the current trap state
/// Returns an array of backtrace frames
pub fn DWARFBuilder::capture_backtrace(
  self : DWARFBuilder,
) -> Array[BacktraceFrame] {
  let pc = @jit_ffi.c_jit_get_trap_pc()
  let fp = @jit_ffi.c_jit_get_trap_fp()
  let lr = @jit_ffi.c_jit_get_trap_lr()
  if pc == 0L {
    return []
  }
  // Capture up to 32 frames
  // Use the extended function that includes LR for when FP is 0
  let max_frames = 32
  let frames_buf = FixedArray::make(max_frames * 2, 0L)
  let frame_count = @jit_ffi.c_dwarf_capture_backtrace_ex(
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
  let sb = StringBuilder::new()
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
