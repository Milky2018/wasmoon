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
#borrow(self)
pub extern "c" fn GCHeapHandle::reference_candidates(
  self : GCHeapHandle,
  reference : Int32,
) -> FixedArray[Int64] = "wasmoon_gc_heap_reference_candidates"

///|
#borrow(self, bytes, objects)
pub extern "c" fn GCHeapHandle::bind_reservations(
  self : GCHeapHandle,
  bytes : Reservation,
  objects : Reservation,
) -> Bool = "wasmoon_gc_heap_bind_reservations"

///|
#borrow(self)
pub extern "c" fn GCHeapHandle::quota_denied(self : GCHeapHandle) -> Int32 = "wasmoon_gc_heap_quota_denied"

///|
// Borrowed C stack request. It must not escape the synchronous callback.
#external
priv type AllocationRequest

///|
extern "c" fn AllocationRequest::attempt(self : AllocationRequest) -> Int32 = "wasmoon_gc_allocation_attempt"

///|
extern "c" fn AllocationRequest::collect(self : AllocationRequest) -> Int32 = "wasmoon_gc_allocation_collect"

///|
extern "c" fn AllocationRequest::denial(self : AllocationRequest) -> Int32 = "wasmoon_gc_allocation_denial"

///|
#borrow(state)
extern "c" fn allocate_heap(
  capacity : Int64,
  policy : FuncRef[(AllocationRequest, Int32) -> Int32],
  state : CollectionState,
  collection : FuncRef[(CollectionState, CollectionRequest, Bool) -> Int32],
) -> GCHeapHandle = "wasmoon_gc_heap_new"

///|
// Positive results are native object identities; negative results are trap
// codes from trap_codes.h. Return before C frees buffers and transfers control.
fn allocate(request : AllocationRequest, wide : Int32) -> Int32 {
  // Preserve the existing word/slot retry budgets in this first migration.
  let collections = if wide != 0 { 1 } else { 3 }
  // C already attempted the first physical allocation. Enter this callback
  // only after failure, so ordinary successful allocation stays native.
  for attempt = 0; attempt < collections; attempt = attempt + 1 {
    if request.collect() < 0 {
      return -10 // Collection could not preserve precise roots
    }
    let reference = request.attempt()
    if reference > 0 {
      return reference
    }
  }
  match request.denial() {
    1 => -25 // GC payload byte quota
    2 => -26 // GC identity slot quota
    _ => -9 // Allocation exhaustion
  }
}

///|
/// Create a managed heap with the closed native allocation policy installed.
pub fn GCHeapHandle::new(capacity : Int64) -> GCHeapHandle {
  allocate_heap(
    capacity,
    fn(request, wide) { allocate(request, wide) },
    { visitor: None, collecting: false, },
    fn(state, request, rollback) { state.collect(request, rollback) },
  )
}
