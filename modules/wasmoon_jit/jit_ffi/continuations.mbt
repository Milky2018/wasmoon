///|
type NativeContinuationArena

///|
pub extern "c" fn NativeContinuationArena::new() -> NativeContinuationArena = "wasmoon_continuation_arena_new"

///|
#borrow(self)
pub extern "c" fn NativeContinuationArena::clear(
  self : NativeContinuationArena,
) -> Unit = "wasmoon_continuation_arena_clear"
