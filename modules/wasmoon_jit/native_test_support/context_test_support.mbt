///|
pub extern "c" fn context_optional_state() -> Int = "wasmoon_test_context_optional_state"

///|
#borrow(first, second)
pub extern "c" fn shared_callable_registry(
  first : @callable.NativeCallableRegistry,
  second : @callable.NativeCallableRegistry,
) -> Int = "wasmoon_test_shared_callable_registry"
