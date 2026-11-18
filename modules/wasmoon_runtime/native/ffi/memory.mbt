///|
pub using @exec_memory {
  type ExecCodeHandle,
  alloc_exec_managed,
  stage_exec_managed,
  finalize_exec_managed,
  release_exec_managed,
  exec_code_pointer,
}

///|
/// Shared managed linear-memory allocation. Each handle keeps the descriptor
/// and its backing memory alive independently of a Store or JIT context.
pub type MemoryDescriptor

///|
pub extern "c" fn MemoryDescriptor::null() -> MemoryDescriptor = "wasmoon_memory_descriptor_empty"

///|
#borrow(self)
pub extern "c" fn MemoryDescriptor::is_null(self : MemoryDescriptor) -> Bool = "wasmoon_memory_descriptor_is_empty"

///|
#borrow(a, b)
extern "c" fn descriptor_equal(
  a : MemoryDescriptor,
  b : MemoryDescriptor,
) -> Bool = "wasmoon_memory_descriptor_equal"

///|
pub impl Eq for MemoryDescriptor with fn equal(a, b) {
  descriptor_equal(a, b)
}

///|
pub impl Debug for MemoryDescriptor with fn to_repr(self) {
  Repr::literal(
    if self.is_null() {
      "MemoryDescriptor(null)"
    } else {
      "MemoryDescriptor(non-null)"
    },
  )
}

///|
pub extend MemoryDescriptor with Eq::{equal, not_equal}

///|
pub extend MemoryDescriptor with Debug::{to_repr}

///|
#borrow(self, reservation)
pub extern "c" fn MemoryDescriptor::bind_reservation(
  self : MemoryDescriptor,
  reservation : Reservation,
) -> Bool = "wasmoon_memory_bind_reservation"

///|
#borrow(self, quota)
pub extern "c" fn MemoryDescriptor::matches_quota(
  self : MemoryDescriptor,
  quota : Quota,
) -> Int32 = "wasmoon_memory_matches_quota"
