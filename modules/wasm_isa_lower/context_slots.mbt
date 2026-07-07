///|
/// Context slot roles required by reusable Wasm-to-ISA lowering.
///
/// The numeric ids are embedding-defined handles into the generic MachV
/// embedding context layout. Product-specific runtimes own the concrete ids.
pub(all) struct WasmContextSlots {
  memory0_base : Int
  function_table : Int
  table0_base : Int
  table_directory : Int
  memory_directory : Int
  pointer_stride : Int
}

///|
pub fn context_slot_cache_key(slot_id : Int) -> Int {
  -slot_id - 1
}
