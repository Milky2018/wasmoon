///|
/// Whether a context slot can change while generated code for one function runs.
pub(all) enum ContextSlotMutability {
  Immutable
  Mutable
} derive(Eq, Debug)

///|
/// Optional physical-register cache role for a context-derived pointer.
pub(all) enum ContextSlotCacheRole {
  NoContextCache
  ContextCache0Descriptor
  ContextCache0Source
  ContextCache1
} derive(Eq, Debug)

///|
/// Opaque embedding-context slot metadata.
///
/// The `id` is owned by the embedding adapter. Reusable infrastructure may use
/// `offset`, `mutability`, and `cache_role` facts without interpreting what the
/// slot represents.
pub(all) struct ContextSlot {
  id : Int
  offset : Int
  mutability : ContextSlotMutability
  cache_role : ContextSlotCacheRole
} derive(Eq, Debug)

///|
/// Machine-level offsets for an embedding-provided runtime context.
///
/// MachV treats these as opaque offsets from the context base register. The
/// embedding owns the concrete runtime structure and translates its layout into
/// this shape before invoking lowering or emission.
pub(all) struct EmbeddingContextLayout {
  slots : Array[ContextSlot]
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

///|
pub fn EmbeddingContextLayout::slot(
  self : EmbeddingContextLayout,
  id : Int,
) -> ContextSlot? {
  for slot in self.slots {
    if slot.id == id {
      return Some(slot)
    }
  }
  None
}

///|
pub fn EmbeddingContextLayout::slot_offset(
  self : EmbeddingContextLayout,
  id : Int,
) -> Int? {
  match self.slot(id) {
    Some(slot) => Some(slot.offset)
    None => None
  }
}
