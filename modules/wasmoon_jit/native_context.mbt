/// Managed native JIT context ownership and scoped pointer access.

///|
struct NativeJITContext {
  handle : JITContext
  jit_tables : Array[JITTable?]
}

///|
pub fn NativeJITContext::try_alloc(total_funcs : Int) -> NativeJITContext? {
  let context : NativeJITContext = {
    handle: c_jit_alloc_context_managed(total_funcs),
    jit_tables: [],
  }
  if context.with_ptr(fn(ptr) { ptr != 0L }) {
    Some(context)
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
