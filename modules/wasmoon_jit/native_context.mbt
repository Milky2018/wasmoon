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
  if c_jit_context_is_valid(context.handle) != 0 {
    Some(context)
  } else {
    None
  }
}
