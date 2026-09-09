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
