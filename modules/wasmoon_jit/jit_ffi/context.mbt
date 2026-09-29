///|
/// Managed native context. Its finalizer releases retained native views and arrays.
pub type JITContext

///|
pub extern "c" fn JITContext::new(func_count : Int) -> JITContext = "wasmoon_jit_alloc_context_managed"

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
