///|
type NativeContinuationArena

///|
extern "c" fn NativeContinuationArena::allocate() -> NativeContinuationArena = "wasmoon_continuation_arena_new"

///|
#borrow(self)
extern "c" fn NativeContinuationArena::is_available(
  self : NativeContinuationArena,
) -> Bool = "wasmoon_continuation_arena_is_available"

///|
pub fn NativeContinuationArena::new() -> NativeContinuationArena raise NativeAllocationError {
  let arena = NativeContinuationArena::allocate()
  guard arena.is_available() else { raise OutOfMemory }
  arena
}

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

///|
#borrow(self)
pub extern "c" fn NativeContinuationArena::is_live(
  self : NativeContinuationArena,
  reference : Int64,
) -> Bool = "wasmoon_continuation_arena_is_live"
