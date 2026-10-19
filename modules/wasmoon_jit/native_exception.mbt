///|
pub fn NativeJITContext::set_exception_arena(
  self : NativeJITContext,
  arena : NativeExceptionArena,
) -> Unit {
  self.handle.bind_exception_arena(arena)
}
