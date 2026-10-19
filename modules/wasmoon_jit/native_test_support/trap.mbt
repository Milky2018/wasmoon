///|
pub extern "c" fn trap_signal_masks() -> Int32 = "wasmoon_test_trap_signal_masks"

///|
#borrow(context)
extern "c" fn native_failure_recovery_raw(
  context : @jit_ffi.JITContext,
) -> Int32 = "wasmoon_test_native_failure_recovery"

///|
pub fn native_failure_recovery() -> Int32 {
  native_failure_recovery_raw(@jit_ffi.JITContext::new(0))
}
