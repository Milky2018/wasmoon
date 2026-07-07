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
const WASMOON_CONTEXT_SLOT_MEMORY0_DESCRIPTOR : Int = 0

///|
const WASMOON_CONTEXT_SLOT_MEMORY0_BASE : Int = 1

///|
const WASMOON_CONTEXT_SLOT_FUNCTION_TABLE : Int = 2

///|
const WASMOON_CONTEXT_SLOT_TABLE0_BASE : Int = 3

///|
const WASMOON_CONTEXT_SLOT_TABLE_DIRECTORY : Int = 4

///|
const WASMOON_CONTEXT_SLOT_GLOBAL_STORAGE : Int = 5

///|
const WASMOON_CONTEXT_SLOT_MEMORY_DIRECTORY : Int = 6

///|
const WASMOON_CONTEXT_SLOT_DEBUG_CURRENT_FUNCTION : Int = 7

///|
const WASMOON_CONTEXT_SLOT_GC_ALLOCATION_CURSOR : Int = 8

///|
const WASMOON_CONTEXT_SLOT_GC_ALLOCATION_LIMIT : Int = 9

///|
pub fn wasm_context_slots() -> @wasm_isa_lower.WasmContextSlots {
  {
    memory0_base: WASMOON_CONTEXT_SLOT_MEMORY0_BASE,
    function_table: WASMOON_CONTEXT_SLOT_FUNCTION_TABLE,
    table0_base: WASMOON_CONTEXT_SLOT_TABLE0_BASE,
    table_directory: WASMOON_CONTEXT_SLOT_TABLE_DIRECTORY,
    memory_directory: WASMOON_CONTEXT_SLOT_MEMORY_DIRECTORY,
    pointer_stride: vmcontext_layout().pointer_stride,
  }
}

///|
/// Translate Wasmoon's concrete VMContext prefix into the generic machine-level
/// embedding context layout consumed by reusable code.
pub fn VMContextLayout::to_embedding_context_layout(
  self : VMContextLayout,
) -> @abi.EmbeddingContextLayout {
  {
    slots: [
      {
        id: WASMOON_CONTEXT_SLOT_MEMORY0_DESCRIPTOR,
        offset: self.memory0_offset,
        mutability: Immutable,
        cache_role: ContextCache0Descriptor,
      },
      {
        id: WASMOON_CONTEXT_SLOT_MEMORY0_BASE,
        offset: self.memory0_base_offset,
        mutability: Mutable,
        cache_role: ContextCache0Source,
      },
      {
        id: WASMOON_CONTEXT_SLOT_FUNCTION_TABLE,
        offset: self.func_table_offset,
        mutability: Immutable,
        cache_role: ContextCache1,
      },
      {
        id: WASMOON_CONTEXT_SLOT_TABLE0_BASE,
        offset: self.table0_base_offset,
        mutability: Mutable,
        cache_role: NoContextCache,
      },
      {
        id: WASMOON_CONTEXT_SLOT_TABLE_DIRECTORY,
        offset: self.tables_offset,
        mutability: Mutable,
        cache_role: NoContextCache,
      },
      {
        id: WASMOON_CONTEXT_SLOT_GLOBAL_STORAGE,
        offset: self.globals_offset,
        mutability: Immutable,
        cache_role: NoContextCache,
      },
      {
        id: WASMOON_CONTEXT_SLOT_MEMORY_DIRECTORY,
        offset: self.memories_offset,
        mutability: Mutable,
        cache_role: NoContextCache,
      },
      {
        id: WASMOON_CONTEXT_SLOT_DEBUG_CURRENT_FUNCTION,
        offset: self.debug_current_func_idx_offset,
        mutability: Mutable,
        cache_role: NoContextCache,
      },
      {
        id: WASMOON_CONTEXT_SLOT_GC_ALLOCATION_CURSOR,
        offset: self.gc_heap_ptr_offset,
        mutability: Mutable,
        cache_role: NoContextCache,
      },
      {
        id: WASMOON_CONTEXT_SLOT_GC_ALLOCATION_LIMIT,
        offset: self.gc_heap_limit_offset,
        mutability: Mutable,
        cache_role: NoContextCache,
      },
    ],
    active_function_index_slot: Some(
      WASMOON_CONTEXT_SLOT_DEBUG_CURRENT_FUNCTION,
    ),
    allocation_cursor_slot: Some(WASMOON_CONTEXT_SLOT_GC_ALLOCATION_CURSOR),
    allocation_limit_slot: Some(WASMOON_CONTEXT_SLOT_GC_ALLOCATION_LIMIT),
  }
}

///|
pub fn embedding_context_layout() -> @abi.EmbeddingContextLayout {
  vmcontext_layout().to_embedding_context_layout()
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
