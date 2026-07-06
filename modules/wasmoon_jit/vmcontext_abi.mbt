///|
/// Fixed VMContext prefix layout accessed by generated JIT code.
///
/// Keep these offsets in sync with `jit_ffi/jit_ffi.h::jit_context_t`.
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
pub fn vmcontext_layout() -> VMContextLayout {
  {
    memory0_offset: 0,
    memory0_base_offset: 8,
    memory0_size_offset: 16,
    func_table_offset: 24,
    table0_base_offset: 32,
    table0_elements_offset: 40,
    globals_offset: 48,
    tables_offset: 56,
    table_count_offset: 64,
    func_count_offset: 68,
    table_sizes_offset: 72,
    table_max_sizes_offset: 80,
    memories_offset: 88,
    memory_count_offset: 96,
    debug_current_func_idx_offset: 100,
    gc_heap_ptr_offset: 104,
    gc_heap_limit_offset: 112,
    gc_heap_offset: 120,
    pointer_stride: 8,
    global_value_stride: 16,
    table_entry_value_offset: 0,
    table_entry_stride: 16,
    func_table_entry_stride: 8,
  }
}

///|
/// Translate Wasmoon's concrete VMContext prefix into the generic machine-level
/// runtime context layout consumed by lowering and emission.
pub fn VMContextLayout::to_runtime_context_layout(
  self : VMContextLayout,
) -> @abi.RuntimeContextLayout {
  {
    primary_memory_descriptor_offset: self.memory0_offset,
    primary_memory_base_offset: self.memory0_base_offset,
    function_table_offset: self.func_table_offset,
    primary_table_base_offset: self.table0_base_offset,
    table_directory_offset: self.tables_offset,
    global_storage_offset: self.globals_offset,
    memory_directory_offset: self.memories_offset,
    debug_current_function_offset: self.debug_current_func_idx_offset,
    gc_allocation_cursor_offset: self.gc_heap_ptr_offset,
    gc_allocation_limit_offset: self.gc_heap_limit_offset,
    pointer_stride: self.pointer_stride,
  }
}

///|
pub fn runtime_context_layout() -> @abi.RuntimeContextLayout {
  vmcontext_layout().to_runtime_context_layout()
}

///|
/// Fixed prefix layout of `wasmoon_memory_t` accessed by generated JIT code.
///
/// Keep these offsets in sync with `jit_ffi/jit_ffi.h::wasmoon_memory_t`.
pub(all) struct MemoryDescriptorLayout {
  base_offset : Int
  current_length_offset : Int
}

///|
pub fn memory_descriptor_layout() -> MemoryDescriptorLayout {
  { base_offset: 0, current_length_offset: 8 }
}
