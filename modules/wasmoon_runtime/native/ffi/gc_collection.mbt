///|
// The native heap retains this state. It never retains the heap itself; a Store
// visitor is installed only within the existing execution/collection scope.
priv struct CollectionState {
  mut visitor : ((Int32, FixedArray[Int64]) -> FixedArray[Int64])?
  mut collecting : Bool
  mut young_visitor : ((FixedArray[Int64]) -> FixedArray[Int64]?)?
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
  state.young_visitor = None
  if !state.collecting {
    self.set_precise_roots(true)
  }
}

///|
#borrow(self)
extern "c" fn GCHeapHandle::enable_generations(self : GCHeapHandle) -> Unit = "wasmoon_gc_heap_enable_generations"

///|
/// Opt into young collection with a read-only complete young-root expansion.
/// None declines before marking; [-2] reports incomplete discovery. The young
/// callback must use begin_young_trace and must not mutate the heap. General
/// phases0/1/2 keep their existing contract. Write tracking lasts for this heap;
/// clearing/replacing the visitor disables young collection, not edge tracking.
/// Published reference fields must contain valid typed values. Every reference
/// mutation must use the heap write barrier, including writes
/// between execution scopes. Constructor initialization must not cross a safepoint.
pub fn GCHeapHandle::bind_generational_root_visitor(
  self : GCHeapHandle,
  visitor : (Int32, FixedArray[Int64]) -> FixedArray[Int64],
  young_visitor : (FixedArray[Int64]) -> FixedArray[Int64]?,
) -> Unit {
  guard !self.is_null() else { return }
  self.bind_root_visitor(visitor)
  self.collection_state().young_visitor = Some(young_visitor)
  self.enable_generations()
}

///|
pub fn GCHeapHandle::clear_root_visitor(self : GCHeapHandle) -> Unit {
  guard !self.is_null() else { return }
  let state = self.collection_state()
  state.visitor = None
  state.young_visitor = None
  if !state.collecting {
    self.set_precise_roots(false)
  }
}

///|
// Origin, native capability, mature bytes, previous-major bytes, young cycles.
extern "c" fn CollectionRequest::generation(
  self : CollectionRequest,
) -> FixedArray[Int64] = "wasmoon_gc_collection_generation"

///|
extern "c" fn CollectionRequest::prepare(
  self : CollectionRequest,
  young : Bool,
  budget : Int64,
) -> Unit = "wasmoon_gc_collection_prepare"

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
  let result = trace_and_reclaim(
    request,
    self.visitor,
    self.young_visitor,
    rollback,
  )
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
  young_visitor : ((FixedArray[Int64]) -> FixedArray[Int64]?)?,
  rollback : Bool,
) -> Int32 {
  // Retain one visitor for the entire protocol. Binding changes apply only to
  // the next collection; the native mark mode is updated by the outer scope.
  match visitor {
    Some(visit) => {
      let budget = 16L * 1024L * 1024L
      // Keep major cadence independent of nursery size: shrinking the nursery
      // must not multiply full-graph scans for the same nominal allocation.
      let max_young_cycles = 1024L * 1024L * 1024L / budget
      let mut allocation_budget = 0L
      let mut expanded : FixedArray[Int64]? = None
      if !rollback && young_visitor is Some(young_visit) {
        let state = request.generation()
        let growth_budget = state[3].max(budget)
        if state[0] != 0L && state[1] != 0L {
          // A periodic major must keep the nursery allowance. Reverting to a
          // live-set-sized budget makes large heaps allocate another mature
          // heap's worth of garbage before the next young collection.
          allocation_budget = budget
          // Bound mature garbage retention even when promotion is almost empty.
          if state[4] < max_young_cycles && state[2] - state[3] < growth_budget {
            request.prepare(true, budget)
            let seeds = request.seeds()
            expanded = if roots_unavailable(seeds) {
              Some(seeds)
            } else {
              young_visit(seeds)
            }
            if expanded is None {
              allocation_budget = 0L
            }
          }
        }
      }
      let expanded = match expanded {
        Some(roots) => roots
        None => {
          request.prepare(false, allocation_budget)
          let seeds = request.seeds()
          if roots_unavailable(seeds) {
            seeds
          } else {
            visit(0, seeds)
          }
        }
      }
      if roots_unavailable(expanded) {
        request.abort()
        visit(2, []) |> ignore
        return if rollback { 0 } else { -1 }
      }
      request.mark(expanded)
    }
    None => {
      request.prepare(false, 0L)
      request.mark_conservative()
    }
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
