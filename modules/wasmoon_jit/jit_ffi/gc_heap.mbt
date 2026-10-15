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

///|
#borrow(self, visitor)
extern "c" fn GCHeapHandle::bind_root_visitor_raw(
  self : GCHeapHandle,
  trampoline : FuncRef[
    ((Int32, FixedArray[Int64]) -> FixedArray[Int64], Int32, FixedArray[Int64]) -> FixedArray[
      Int64,
    ],
  ],
  visitor : (Int32, FixedArray[Int64]) -> FixedArray[Int64],
) -> Unit = "wasmoon_gc_heap_bind_root_visitor"

///|
pub fn GCHeapHandle::bind_root_visitor(
  self : GCHeapHandle,
  visitor : (Int32, FixedArray[Int64]) -> FixedArray[Int64],
) -> Unit {
  self.bind_root_visitor_raw(
    fn(callback, phase, roots) { callback(phase, roots) },
    visitor,
  )
}

///|
#borrow(self)
pub extern "c" fn GCHeapHandle::clear_root_visitor(self : GCHeapHandle) -> Unit = "wasmoon_gc_heap_clear_root_visitor"

///|
#borrow(self)
pub extern "c" fn GCHeapHandle::reference_candidates(
  self : GCHeapHandle,
  reference : Int32,
) -> FixedArray[Int64] = "wasmoon_gc_heap_reference_candidates"
