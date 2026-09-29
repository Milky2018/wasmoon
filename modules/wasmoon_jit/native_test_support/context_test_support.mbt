///|
pub extern "c" fn context_optional_state() -> Int = "wasmoon_test_context_optional_state"

///|
pub extern "c" fn safepoint_ownership() -> Int = "wasmoon_test_safepoint_ownership"

///|
#borrow(view)
extern "c" fn lookup_view(
  view : @callable.NativeCallableView,
  value : Int64,
) -> Int = "wasmoon_test_callable_lookup"

///|
pub fn callable_lookup(
  registry : @callable.NativeCallableRegistry,
  value : Int64,
) -> Int {
  lookup_view(registry.native_view(), value)
}

///|
#borrow(context)
pub extern "c" fn context_callable_lookup(
  context : @jit_ffi.JITContext,
  value : Int64,
) -> Int = "wasmoon_test_context_callable_lookup"

///|
#borrow(context)
pub extern "c" fn context_callable_subtype(
  context : @jit_ffi.JITContext,
  value : Int64,
  expected : Int,
) -> Int = "wasmoon_test_context_callable_subtype"

///|
#borrow(context)
pub extern "c" fn context_callable_tag(context : @jit_ffi.JITContext) -> Int = "wasmoon_test_context_callable_tag"

///|
pub extern "c" fn activation_scratch_isolation() -> Int = "wasmoon_test_activation_scratch_isolation"

///|
pub extern "c" fn activation_resume_roots() -> Int = "wasmoon_test_activation_resume_roots"
