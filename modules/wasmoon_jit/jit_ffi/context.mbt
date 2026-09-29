///|
/// Managed native context. Its finalizer releases retained native views and arrays.
pub type JITContext

///|
#external
priv type FunctionAddress

///|
extern "c" fn null_function_address() -> FunctionAddress = "wasmoon_jit_null_function_address"

///|
#owned(functions)
extern "c" fn allocate_context(
  functions : FixedArray[FunctionAddress],
) -> JITContext = "wasmoon_jit_alloc_context_with_functions_managed"

///|
extern "c" fn allocate_legacy_context(count : Int) -> JITContext = "wasmoon_jit_alloc_context_managed"

///|
pub fn JITContext::new(func_count : Int) -> JITContext {
  if func_count < 0 {
    // Keep the legacy nullable result for invalid counts.
    return allocate_legacy_context(func_count)
  }
  allocate_context(FixedArray::make(func_count, null_function_address()))
}

///|
#borrow(context, view, locals, tags)
extern "c" fn bind_callable_view(
  context : JITContext,
  view : @callable.NativeCallableView,
  locals : FixedArray[Int],
  local_count : Int,
  tags : FixedArray[Int],
  tag_count : Int,
) -> Unit = "wasmoon_jit_bind_callable_registry"

///|
/// Retain the shared view and per-instance mappings without copying their storage.
/// Callers must not mutate these mappings during guest execution.
pub fn JITContext::bind_callable_registry(
  self : JITContext,
  registry : @callable.NativeCallableRegistry,
  locals : FixedArray[Int],
  tags : FixedArray[Int],
) -> Unit {
  bind_callable_view(
    self,
    registry.native_view(),
    locals,
    locals.length(),
    tags,
    tags.length(),
  )
}
