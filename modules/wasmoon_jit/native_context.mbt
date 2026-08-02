/// Managed native JIT context ownership and scoped pointer access.

///|
struct NativeJITContext {
  handle : JITContext
  jit_tables : Array[JITTable?]
}

///|
pub fn NativeJITContext::try_alloc(total_funcs : Int) -> NativeJITContext? {
  let ctx = c_jit_alloc_context_managed(total_funcs)
  if c_jit_context_ptr(ctx) != 0L {
    Some({ handle: ctx, jit_tables: [] })
  } else {
    None
  }
}

///|
fn[T] NativeJITContext::with_ptr(
  self : NativeJITContext,
  body : (Int64) -> T raise?,
) -> T raise? {
  let ptr = c_jit_context_ptr(self.handle)
  defer c_jit_context_keep_alive(self.handle)
  body(ptr)
}
