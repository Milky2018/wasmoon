///|
extern "c" fn c_hostcall_probe_trampoline() -> Int64 = "wasmoon_test_hostcall_probe_trampoline"

///|
extern "c" fn c_fiber_stack_hostcall_probe_trampoline() -> Int64 = "wasmoon_test_fiber_stack_hostcall_probe_trampoline"

///|
extern "c" fn c_nested_hostcall_tls_probe_trampoline() -> Int64 = "wasmoon_test_nested_hostcall_tls_probe_trampoline"

///|
extern "c" fn c_nested_trap_probe() -> Int64 = "wasmoon_test_nested_trap_probe"

///|
extern "c" fn c_parked_gc_root_probe() -> Int64 = "wasmoon_test_parked_gc_root_probe"

///|
extern "c" fn c_fiber_guard_rejects_access() -> Int = "wasmoon_test_fiber_guard_rejects_access"

///|
extern "c" fn c_fiber_preserves_registers() -> Int = "wasmoon_test_fiber_preserves_registers"

///|
type CallbackCapture

///|
extern "c" fn c_callback_capture_new() -> CallbackCapture = "wasmoon_test_callback_capture_new"

///|
#borrow(capture)
extern "c" fn c_callback_capture_touch(capture : CallbackCapture) -> Unit = "wasmoon_test_callback_capture_touch"

///|
extern "c" fn c_callback_capture_reset() -> Unit = "wasmoon_test_callback_capture_reset"

///|
extern "c" fn c_callback_capture_release_count() -> Int = "wasmoon_test_callback_capture_release_count"

///|
#owned(closure)
extern "c" fn c_set_null_cancellation_callback(
  ctx_ptr : Int64,
  call_closure : FuncRef[(() -> Bool) -> Int],
  closure : () -> Bool,
) -> Unit = "wasmoon_jit_set_cancellation_callback"

///|
#owned(closure)
extern "c" fn c_set_null_wasi_stdin_callback(
  ctx_ptr : Int64,
  call_closure : FuncRef[(() -> Bytes) -> Bytes],
  closure : () -> Bytes,
) -> Unit = "wasmoon_jit_set_wasi_stdin_callback"

///|
pub fn callback_capture() -> CallbackCapture {
  c_callback_capture_new()
}

///|
pub fn CallbackCapture::touch(self : CallbackCapture) -> Unit {
  c_callback_capture_touch(self)
}

///|
pub fn reset_callback_capture() -> Unit {
  c_callback_capture_reset()
}

///|
pub fn callback_capture_release_count() -> Int {
  c_callback_capture_release_count()
}

///|
pub fn transfer_cancellation_callback_to_null_context(
  callback : () -> Bool,
) -> Unit {
  let call_closure : FuncRef[(() -> Bool) -> Int] = fn(f : () -> Bool) {
    if f() {
      1
    } else {
      0
    }
  }
  c_set_null_cancellation_callback(0L, call_closure, callback)
}

///|
pub fn transfer_wasi_stdin_callback_to_null_context(
  callback : () -> Bytes,
) -> Unit {
  let call_closure : FuncRef[(() -> Bytes) -> Bytes] = fn(f : () -> Bytes) {
    f()
  }
  c_set_null_wasi_stdin_callback(0L, call_closure, callback)
}

///|
pub fn hostcall_probe_trampoline() -> Int64 {
  c_hostcall_probe_trampoline()
}

///|
pub fn fiber_stack_hostcall_probe_trampoline() -> Int64 {
  c_fiber_stack_hostcall_probe_trampoline()
}

///|
pub fn nested_hostcall_tls_probe_trampoline() -> Int64 {
  c_nested_hostcall_tls_probe_trampoline()
}

///|
pub fn nested_trap_probe() -> Int64 {
  c_nested_trap_probe()
}

///|
pub fn parked_gc_root_probe() -> Int64 {
  c_parked_gc_root_probe()
}

///|
pub fn fiber_guard_rejects_access() -> Bool {
  c_fiber_guard_rejects_access() == 1
}

///|
pub fn fiber_preserves_registers() -> Bool {
  c_fiber_preserves_registers() == 1
}
