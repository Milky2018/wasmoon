///|
/// Owns one native wait registration, including its memory descriptor lease.
/// Dropping the object cancels its registration; explicit cancellation is
/// idempotent. Creation requires a checked, aligned shared-memory address.
pub type NativeAtomicWait

///|
extern "c" fn atomic_wait_new(
  descriptor : Int64,
  offset : Int64,
  width : Int,
  expected : Int64,
  timeout : Int64,
) -> NativeAtomicWait = "wasmoon_atomic_wait_managed"

///|
#borrow(self)
extern "c" fn NativeAtomicWait::allocated(self : NativeAtomicWait) -> Bool = "wasmoon_atomic_wait_managed_allocated"

///|
/// Returns -1 while pending, or the Wasm wait result 0/1/2. After cancellation
/// returns 3. Polling never blocks the embedding thread.
#borrow(self)
pub extern "c" fn NativeAtomicWait::poll(self : NativeAtomicWait) -> Int = "wasmoon_atomic_wait_managed_poll"

///|
#borrow(self)
pub extern "c" fn NativeAtomicWait::cancel(self : NativeAtomicWait) -> Unit = "wasmoon_atomic_wait_managed_cancel"

///|
/// Request a one-millisecond sleep when the registration is still pending.
/// Cooperative schedulers use poll instead.
#borrow(self)
pub extern "c" fn NativeAtomicWait::pause(self : NativeAtomicWait) -> Unit = "wasmoon_atomic_wait_pause"

///|
pub fn atomic_wait_begin(
  descriptor : Int64,
  offset : Int64,
  width : Int,
  expected : Int64,
  timeout : Int64,
) -> NativeAtomicWait? {
  let waiter = atomic_wait_new(descriptor, offset, width, expected, timeout)
  if waiter.allocated() {
    Some(waiter)
  } else {
    None
  }
}

///|
pub extern "c" fn atomic_notify(
  descriptor : Int64,
  offset : Int64,
  count : Int,
) -> Int = "wasmoon_atomic_notify"

///|
extern "c" fn c_jit_get_atomic_wait32_ptr() -> Int64 = "wasmoon_jit_get_atomic_wait32_ptr"

///|
extern "c" fn c_jit_get_atomic_wait64_ptr() -> Int64 = "wasmoon_jit_get_atomic_wait64_ptr"

///|
extern "c" fn c_jit_get_atomic_notify_ptr() -> Int64 = "wasmoon_jit_get_atomic_notify_ptr"
