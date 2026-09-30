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

///|
#borrow(context)
pub extern "c" fn context_gc_funcref_subtype(
  context : @jit_ffi.JITContext,
  function : Int,
  expected : Int,
) -> Int = "wasmoon_test_context_gc_funcref_subtype"

///|
#borrow(context)
pub extern "c" fn context_gc_legacy_rebind(
  context : @jit_ffi.JITContext,
) -> Int = "wasmoon_test_context_gc_legacy_rebind"

///|
#borrow(context, types, canonical, functions)
pub extern "c" fn context_gc_metadata_shares(
  context : @jit_ffi.JITContext,
  types : FixedArray[Int],
  canonical : FixedArray[Int],
  functions : FixedArray[Int],
) -> Int = "wasmoon_test_context_gc_metadata_shares"

///|
#borrow(context, blob, offsets, addresses)
pub extern "c" fn context_gc_payload_shares(
  context : @jit_ffi.JITContext,
  blob : Bytes,
  offsets : FixedArray[Int],
  addresses : FixedArray[Int64],
) -> Int = "wasmoon_test_context_gc_payload_shares"

///|
#borrow(context)
pub extern "c" fn context_gc_payload_valid(
  context : @jit_ffi.JITContext,
) -> Int = "wasmoon_test_context_gc_payload_valid"

///|
#borrow(context)
pub extern "c" fn context_gc_payload_legacy(
  context : @jit_ffi.JITContext,
) -> Int = "wasmoon_test_context_gc_payload_legacy"

///|
#borrow(context)
pub extern "c" fn context_gc_payload_empty(
  context : @jit_ffi.JITContext,
) -> Int = "wasmoon_test_context_gc_payload_empty"

///|
pub extern "c" fn activation_controls() -> Int = "wasmoon_test_activation_controls"

///|
#borrow(context, data)
pub extern "c" fn context_segments_share_data(
  context : @jit_ffi.JITContext,
  data : Bytes,
) -> Int = "wasmoon_test_context_segments_share_data"

///|
#borrow(context)
pub extern "c" fn context_segments_valid(context : @jit_ffi.JITContext) -> Int = "wasmoon_test_context_segments_valid"

///|
#borrow(context)
pub extern "c" fn context_segments_legacy(context : @jit_ffi.JITContext) -> Int = "wasmoon_test_context_segments_legacy"

///|
#borrow(context)
pub extern "c" fn context_segments_empty(context : @jit_ffi.JITContext) -> Int = "wasmoon_test_context_segments_empty"

///|
#borrow(context)
pub extern "c" fn context_function_array(context : @jit_ffi.JITContext) -> Int = "wasmoon_test_context_function_array"

///|
pub extern "c" fn raw_context_function_array() -> Int = "wasmoon_test_raw_context_function_array"

///|
pub extern "c" fn context_globals_ownership() -> Int = "wasmoon_test_context_globals_ownership"
