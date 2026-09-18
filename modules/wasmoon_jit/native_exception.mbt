///|
#borrow(context, arena)
extern "c" fn bind_exception_arena(
  context : JITContext,
  arena : NativeExceptionArena,
) -> Unit = "wasmoon_exception_arena_bind"

///|
pub fn NativeJITContext::set_exception_arena(
  self : NativeJITContext,
  arena : NativeExceptionArena,
) -> Unit {
  bind_exception_arena(self.handle, arena)
}
