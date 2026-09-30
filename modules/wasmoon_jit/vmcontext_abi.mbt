///|
/// VMContext field offsets accessed by generated JIT code.
///
/// The standalone legacy layout comes from native C declarations; module-shaped
/// layouts come from the shared MoonBit layout builder.
/// Embedders and frontends should query this value instead of copying raw
/// offsets into lowering code.
pub(all) struct VMContextLayout {
  memory0_offset : Int
  memory0_base_offset : Int
  memory0_size_offset : Int
  func_table_offset : Int
  table0_base_offset : Int
  table0_elements_offset : Int
  globals_offset : Int
  tables_offset : Int
  table_count_offset : Int
  func_count_offset : Int
  table_sizes_offset : Int
  table_max_sizes_offset : Int
  memories_offset : Int
  memory_count_offset : Int
  debug_current_func_idx_offset : Int
  gc_heap_ptr_offset : Int
  gc_heap_limit_offset : Int
  gc_heap_offset : Int
  pointer_stride : Int
  global_value_stride : Int
  table_entry_value_offset : Int
  table_entry_stride : Int
  func_table_entry_stride : Int
}

///|
extern "C" fn native_layout_field(index : Int) -> Int = "wasmoon_jit_layout_field"

///|
let native_vmcontext_layout : VMContextLayout = {
  memory0_offset: native_layout_field(0),
  memory0_base_offset: native_layout_field(1),
  memory0_size_offset: native_layout_field(2),
  func_table_offset: native_layout_field(3),
  table0_base_offset: native_layout_field(4),
  table0_elements_offset: native_layout_field(5),
  globals_offset: native_layout_field(6),
  tables_offset: native_layout_field(7),
  table_count_offset: native_layout_field(8),
  func_count_offset: native_layout_field(9),
  table_sizes_offset: native_layout_field(10),
  table_max_sizes_offset: native_layout_field(11),
  memories_offset: native_layout_field(12),
  memory_count_offset: native_layout_field(13),
  debug_current_func_idx_offset: native_layout_field(14),
  gc_heap_ptr_offset: native_layout_field(15),
  gc_heap_limit_offset: native_layout_field(16),
  gc_heap_offset: native_layout_field(17),
  pointer_stride: native_layout_field(18),
  global_value_stride: native_layout_field(19),
  table_entry_value_offset: native_layout_field(20),
  table_entry_stride: native_layout_field(21),
  func_table_entry_stride: native_layout_field(22),
}

///|
pub fn vmcontext_layout() -> VMContextLayout {
  native_vmcontext_layout
}

///|
/// Fixed prefix layout of `wasmoon_memory_t` accessed by generated JIT code.
///
/// Offsets are derived from the native C declarations at initialization.
pub(all) struct MemoryDescriptorLayout {
  base_offset : Int
  current_length_offset : Int
}

///|
let native_memory_layout : MemoryDescriptorLayout = {
  base_offset: native_layout_field(23),
  current_length_offset: native_layout_field(24),
}

///|
pub fn memory_descriptor_layout() -> MemoryDescriptorLayout {
  native_memory_layout
}

///|
pub using @context_layout {type ContextShape}

///|
pub fn context_shape(module_ : @types.Module) -> ContextShape {
  @context_layout.ContextShape::from_module(module_)
}

///|
pub fn shaped_vmcontext_layout(shape : ContextShape) -> VMContextLayout {
  guard shape.descriptor() is Some(offsets) else { return vmcontext_layout() }
  {
    memory0_offset: offsets[0],
    memory0_base_offset: offsets[1],
    memory0_size_offset: offsets[2],
    func_table_offset: offsets[3],
    table0_base_offset: offsets[4],
    table0_elements_offset: offsets[5],
    globals_offset: offsets[6],
    tables_offset: offsets[7],
    table_count_offset: offsets[8],
    func_count_offset: offsets[9],
    table_sizes_offset: offsets[10],
    table_max_sizes_offset: offsets[11],
    memories_offset: offsets[12],
    memory_count_offset: offsets[13],
    debug_current_func_idx_offset: offsets[14],
    gc_heap_ptr_offset: offsets[15],
    gc_heap_limit_offset: offsets[16],
    gc_heap_offset: offsets[17],
    pointer_stride: offsets[18],
    global_value_stride: offsets[19],
    table_entry_value_offset: offsets[20],
    table_entry_stride: offsets[21],
    func_table_entry_stride: offsets[22],
  }
}
