///|
type NativeContinuationArena

///|
pub extern "c" fn NativeContinuationArena::new() -> NativeContinuationArena = "wasmoon_continuation_arena_new"

///|
#borrow(self)
pub extern "c" fn NativeContinuationArena::clear(
  self : NativeContinuationArena,
) -> Unit = "wasmoon_continuation_arena_clear"

///|
#borrow(self)
pub extern "c" fn NativeContinuationArena::gc_roots(
  self : NativeContinuationArena,
  reference : Int64,
) -> FixedArray[Int64] = "wasmoon_continuation_arena_gc_roots"

///|
/// Release consumed handle rows and identities no longer borrowed by scopes.
#borrow(self)
pub extern "c" fn NativeContinuationArena::reclaim_retired(
  self : NativeContinuationArena,
) -> Unit = "wasmoon_continuation_arena_reclaim_retired"
