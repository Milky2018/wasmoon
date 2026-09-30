/// Managed native JIT context ownership and scoped pointer access.

///|
struct NativeJITContext {
  handle : JITContext
  jit_tables : Array[JITTable?]
  mut configured_native_fiber_stack_size : Int64
}

///|
pub fn NativeJITContext::try_alloc(
  total_funcs : Int,
  layout? : @jit_ffi.ContextLayout? = None,
) -> NativeJITContext? {
  let context : NativeJITContext = {
    handle: @jit_ffi.JITContext::new_shaped(total_funcs, layout),
    jit_tables: [],
    configured_native_fiber_stack_size: 0L,
  }
  if c_jit_context_is_valid(context.handle) != 0 {
    Some(context)
  } else {
    None
  }
}

///|
pub using @jit_ffi {type ContextLayout}
