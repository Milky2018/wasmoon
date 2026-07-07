///|
/// Machine-level offsets for an embedding-provided runtime context.
///
/// MachV treats these as opaque offsets from the context base register. The
/// embedding owns the concrete runtime structure and translates its layout into
/// this shape before invoking lowering or emission.
pub(all) struct EmbeddingContextLayout {
  context_cache_0_descriptor_offset : Int
  context_cache_0_source_offset : Int
  function_table_offset : Int
  primary_table_base_offset : Int
  table_directory_offset : Int
  global_storage_offset : Int
  memory_directory_offset : Int
  debug_current_function_offset : Int
  gc_allocation_cursor_offset : Int
  gc_allocation_limit_offset : Int
  pointer_stride : Int
}

///|
/// Compatibility alias for lowering code that still uses the old name.
pub type RuntimeContextLayout = EmbeddingContextLayout
