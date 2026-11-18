///|
/// Create a new DWARF debug info builder
/// Returns an opaque handle to pass to other DWARF functions
extern "c" fn c_dwarf_create() -> DWARFBuilder = "wasmoon_dwarf_create"

///|
/// Add a function to the DWARF debug info
/// Parameters:
///   dwarf: Handle from c_dwarf_create()
///   name: Function name (null-terminated bytes)
///   addr: Function start address
///   size: Function size in bytes
///   func_idx: WebAssembly function index
#borrow(dwarf, name)
extern "c" fn c_dwarf_add_function(
  dwarf : DWARFBuilder,
  name : Bytes,
  addr : Int64,
  size : Int32,
  func_idx : Int32,
) -> Unit = "wasmoon_dwarf_add_function"

///|
/// Register the DWARF debug info with the debugger (LLDB/GDB)
/// This generates an in-memory Mach-O/ELF object and registers it
/// via the GDB JIT interface
/// verbose: if true, print debug info to stderr
#borrow(dwarf)
extern "c" fn c_dwarf_register(dwarf : DWARFBuilder, verbose : Int32) -> Bool = "wasmoon_dwarf_register"

///|
/// Unregister DWARF debug info from the debugger
#borrow(dwarf)
extern "c" fn c_dwarf_unregister(dwarf : DWARFBuilder) -> Unit = "wasmoon_dwarf_unregister"

///|
/// Destroy the DWARF builder and free resources
/// Also unregisters debug info if registered
#borrow(dwarf)
extern "c" fn c_dwarf_destroy(dwarf : DWARFBuilder) -> Unit = "wasmoon_dwarf_destroy"

///|
/// Set the active DWARF builder for address lookups
/// This is used for backtrace symbolication
#borrow(dwarf)
extern "c" fn c_dwarf_set_active(dwarf : DWARFBuilder) -> Unit = "wasmoon_dwarf_set_active"

///|
/// Lookup an address in the DWARF debug info
/// Returns required UTF-8 name bytes including the terminator, or 0 if absent.
/// If found, writes results to the provided arrays (a zero-sized name buffer probes size).
#borrow(dwarf, name_out, func_idx_out, offset_out)
extern "c" fn c_dwarf_lookup_address(
  dwarf : DWARFBuilder,
  addr : Int64,
  name_out : FixedArray[Byte],
  name_size : Int32,
  func_idx_out : FixedArray[Int32],
  offset_out : FixedArray[Int64],
) -> Int32 = "wasmoon_dwarf_lookup_address"
