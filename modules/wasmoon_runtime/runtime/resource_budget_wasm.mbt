///|
fn Memory::bind_budget(
  self : Memory,
  budget : ResourceBudget,
) -> Unit raise RuntimeError {
  let storage = self.managed_storage()
  match storage.reservation {
    Some(reservation) =>
      if !reservation.matches(budget.native_quota(MemoryBytes)) {
        raise ResourceLimitExceeded(MemoryBytes)
      }
    None =>
      storage.reservation = Some(
        budget.reservation(MemoryBytes, self.byte_len()),
      )
  }
}

///|
/// Admit the temporary representation before decoding/copying an array payload.
/// Release immediately before handing that payload to the heap allocator, which
/// performs the final admission. This bounds staging work, not process RSS.
pub fn Store::reserve_gc_array_work(
  self : Store,
  length : Int32,
) -> (ResourceLease, ResourceLease)? raise RuntimeError {
  self.ensure_open()
  guard length >= 0 && length <= (0x7FFF_FFFF - 32) / 16 else {
    raise AllocationTooLarge
  }
  if self.resource_budget is Some(budget) {
    let bytes = budget.reserve(GcBytes, 32L + length.to_int64() * 16L)
    errdefer bytes.release()
    let objects = budget.reserve(
      GcObjects,
      if self.heap.free_list.is_empty() {
        1L
      } else {
        0L
      },
    )
    Some((bytes, objects))
  } else {
    None
  }
}

///|
/// Allocate a repeated array without constructing an unadmitted temporary array.
pub fn Store::alloc_array_repeated(
  self : Store,
  type_idx : Int32,
  length : Int32,
  value : @types.Value,
  instance? : ModuleInstance,
) -> Int32 raise RuntimeError {
  self.ensure_open()
  guard length >= 0 && length <= (0x7FFF_FFFF - 32) / 16 else {
    raise AllocationTooLarge
  }
  if instance is Some(instance) {
    self.check_instance(instance)
  }
  let reference = self.heap.alloc_array_repeated(type_idx, length, value)
  self.record_gc_type(reference, instance, type_idx)
  reference
}
