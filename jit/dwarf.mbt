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
pub fn DWARFBuilder::register(self : DWARFBuilder) -> Unit {
  @jit_ffi.c_dwarf_register(self.handle)
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
