///|
/// Shared managed GC heap. Contexts and parked root registrations retain it.
pub type GCHeapHandle

///|
pub impl Debug for GCHeapHandle with fn to_repr(_self) {
  Repr::literal("GCHeapHandle")
}

///|
pub extend GCHeapHandle with Debug::{to_repr}

///|
pub extern "c" fn GCHeapHandle::null() -> GCHeapHandle = "wasmoon_gc_heap_empty"

///|
#borrow(self)
pub extern "c" fn GCHeapHandle::is_null(self : GCHeapHandle) -> Bool = "wasmoon_gc_heap_is_empty"
