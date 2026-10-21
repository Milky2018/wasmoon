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
extern "c" fn allocate_legacy_context(count : Int32) -> JITContext = "wasmoon_jit_alloc_context_managed"

///|
pub fn JITContext::new(func_count : Int32) -> JITContext {
  if func_count < 0 {
    // Keep the legacy nullable result for invalid counts.
    return allocate_legacy_context(func_count)
  }
  allocate_context(FixedArray::make(func_count, null_function_address()))
  |> install_exception_factory
}

///|
#borrow(context, view, locals, tags, functions)
extern "c" fn bind_callable_view(
  context : JITContext,
  view : @callable.NativeCallableView,
  locals : FixedArray[Int32],
  local_count : Int32,
  tags : FixedArray[Int32],
  tag_count : Int32,
  functions : FixedArray[Int32],
  function_count : Int32,
) -> Unit = "wasmoon_jit_bind_callable_registry"

///|
/// Retain the shared view and per-instance mappings without copying their storage.
/// Callers must not mutate these mappings during guest execution.
pub fn JITContext::bind_callable_registry(
  self : JITContext,
  registry : @callable.NativeCallableRegistry,
  locals : FixedArray[Int32],
  tags : FixedArray[Int32],
  functions~ : FixedArray[Int32] = [],
) -> Unit {
  bind_callable_view(
    self,
    registry.native_view(),
    locals,
    locals.length(),
    tags,
    tags.length(),
    functions,
    functions.length(),
  )
}

///|
#borrow(self)
#owned(globals)
pub extern "c" fn JITContext::bind_globals(
  self : JITContext,
  globals : FixedArray[Int64],
) -> Int64 = "wasmoon_jit_bind_globals_managed"

///|
#owned(functions, layout)
extern "c" fn allocate_shaped_context(
  functions : FixedArray[FunctionAddress],
  layout : Bytes,
) -> JITContext = "wasmoon_jit_alloc_shaped_context"

///|
pub fn JITContext::new_shaped(
  func_count : Int32,
  layout : ContextLayout?,
) -> JITContext {
  guard layout is Some(layout) else { return JITContext::new(func_count) }
  if func_count < 0 {
    return allocate_legacy_context(-1)
  }
  allocate_shaped_context(
    FixedArray::make(func_count, null_function_address()),
    layout.words(),
  )
  |> install_exception_factory
}
