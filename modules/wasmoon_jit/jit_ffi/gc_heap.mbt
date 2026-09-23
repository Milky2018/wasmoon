///|
/// Borrowed pointer to a C-owned GC heap. Keep the owning CHeap alive until all
/// contexts and exception root registrations using it have been released.
#external
pub type GCHeapHandle

///|
pub impl Debug for GCHeapHandle with fn to_repr(_self) {
  Repr::literal("GCHeapHandle")
}

///|
pub extend GCHeapHandle with Debug::{to_repr}

///|
pub extern "c" fn GCHeapHandle::null() -> GCHeapHandle = "wasmoon_native_pointer_null"

///|
pub extern "c" fn GCHeapHandle::is_null(self : GCHeapHandle) -> Bool = "wasmoon_native_pointer_is_null"
