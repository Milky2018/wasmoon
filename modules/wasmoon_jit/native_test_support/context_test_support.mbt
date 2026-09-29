///|
pub extern "c" fn context_optional_state() -> Int = "wasmoon_test_context_optional_state"

///|
#borrow(first, second)
pub extern "c" fn shared_callable_registry(
  first : @callable.NativeCallableRegistry,
  second : @callable.NativeCallableRegistry,
) -> Int = "wasmoon_test_shared_callable_registry"

///|
pub extern "c" fn safepoint_ownership() -> Int = "wasmoon_test_safepoint_ownership"

///|
#borrow(registry)
pub extern "c" fn callable_lookup(
  registry : @callable.NativeCallableRegistry,
  value : Int64,
) -> Int = "wasmoon_test_callable_lookup"
