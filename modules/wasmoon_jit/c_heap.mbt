///|
pub using @runtime_bridge {
  type CHeapError,
  type CHeap,
  type GcSlot,
  value_to_slot,
  value_to_i64,
  i64_to_value,
  slot_to_value,
  gc_debug_set_fail_alloc,
  type GCHeapHandle,
}
