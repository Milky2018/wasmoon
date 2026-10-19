///|
// The native heap retains this state. It never retains the heap itself; a Store
// visitor is installed only within the existing execution/collection scope.
priv struct CollectionState {
  mut visitor : ((Int32, FixedArray[Int64]) -> FixedArray[Int64])?
  mut collecting : Bool
}

///|
// Borrowed native stack request; no pointer or root buffer may escape the call.
#external
priv type CollectionRequest

///|
#borrow(self)
extern "c" fn GCHeapHandle::collection_state(
  self : GCHeapHandle,
) -> CollectionState = "wasmoon_gc_heap_collection_state"

///|
#borrow(self)
extern "c" fn GCHeapHandle::set_precise_roots(
  self : GCHeapHandle,
  precise : Bool,
) -> Unit = "wasmoon_gc_heap_set_precise_roots"

///|
pub fn GCHeapHandle::bind_root_visitor(
  self : GCHeapHandle,
  visitor : (Int32, FixedArray[Int64]) -> FixedArray[Int64],
) -> Unit {
  guard !self.is_null() else { return }
  let state = self.collection_state()
  state.visitor = Some(visitor)
  if !state.collecting {
    self.set_precise_roots(true)
  }
}

///|
pub fn GCHeapHandle::clear_root_visitor(self : GCHeapHandle) -> Unit {
  guard !self.is_null() else { return }
  let state = self.collection_state()
  state.visitor = None
  if !state.collecting {
    self.set_precise_roots(false)
  }
}

///|
extern "c" fn CollectionRequest::seeds(
  self : CollectionRequest,
) -> FixedArray[Int64] = "wasmoon_gc_collection_seeds"

///|
#borrow(roots)
extern "c" fn CollectionRequest::mark(
  self : CollectionRequest,
  roots : FixedArray[Int64],
) -> Unit = "wasmoon_gc_collection_mark"

///|
extern "c" fn CollectionRequest::mark_conservative(
  self : CollectionRequest,
) -> Unit = "wasmoon_gc_collection_mark_conservative"

///|
extern "c" fn CollectionRequest::abort(self : CollectionRequest) -> Unit = "wasmoon_gc_collection_abort"

///|
extern "c" fn CollectionRequest::reset_auxiliary_marks(
  self : CollectionRequest,
) -> Unit = "wasmoon_gc_collection_reset_auxiliary_marks"

///|
extern "c" fn CollectionRequest::sweep(self : CollectionRequest) -> Int32 = "wasmoon_gc_collection_sweep"

///|
extern "c" fn CollectionRequest::rollback(self : CollectionRequest) -> Unit = "wasmoon_gc_collection_rollback"

///|
extern "c" fn CollectionRequest::sweep_exceptions(
  self : CollectionRequest,
) -> Unit = "wasmoon_gc_collection_sweep_exceptions"

///|
extern "c" fn CollectionRequest::sweep_continuations(
  self : CollectionRequest,
) -> Unit = "wasmoon_gc_collection_sweep_continuations"

///|
extern "c" fn CollectionRequest::set_precise_roots(
  self : CollectionRequest,
  precise : Bool,
) -> Unit = "wasmoon_gc_collection_set_precise_roots"

///|
fn roots_unavailable(roots : FixedArray[Int64]) -> Bool {
  roots.length() == 1 && roots[0] == -2L
}

///|
fn CollectionState::collect(
  self : CollectionState,
  request : CollectionRequest,
  rollback : Bool,
) -> Int32 {
  guard !self.collecting else { return if rollback { 0 } else { -1 } }
  self.collecting = true
  let result = trace_and_reclaim(request, self.visitor, rollback)
  self.collecting = false
  request.set_precise_roots(self.visitor is Some(_))
  result
}

///|
// This protocol is non-raising. Keeping its early returns inside one helper
// gives the outer scope one cleanup point without allocating a defer closure.
fn trace_and_reclaim(
  request : CollectionRequest,
  visitor : ((Int32, FixedArray[Int64]) -> FixedArray[Int64])?,
  rollback : Bool,
) -> Int32 {
  // Retain one visitor for the entire protocol. Binding changes apply only to
  // the next collection; the native mark mode is updated by the outer scope.
  match visitor {
    Some(visit) => {
      let seeds = request.seeds()
      let expanded = if roots_unavailable(seeds) {
        seeds
      } else {
        visit(0, seeds)
      }
      if roots_unavailable(expanded) {
        request.abort()
        visit(2, []) |> ignore
        return if rollback { 0 } else { -1 }
      }
      request.mark(expanded)
    }
    None => request.mark_conservative()
  }
  let collected = if rollback {
    request.rollback()
    1
  } else {
    request.sweep()
  }
  match visitor {
    Some(visit) => {
      request.sweep_exceptions()
      request.sweep_continuations()
      visit(1, []) |> ignore
    }
    None => request.reset_auxiliary_marks()
  }
  collected
}
