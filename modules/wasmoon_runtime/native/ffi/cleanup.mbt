///|
/// A managed cleanup callback. The finalizer calls and releases its closure exactly once;
/// close performs the same cleanup early. The callback must not raise.
pub type CleanupOwner

///|
#owned(action)
extern "c" fn new_cleanup_owner(
  callback : FuncRef[(() -> Unit) -> Unit],
  action : () -> Unit,
) -> CleanupOwner = "wasmoon_cleanup_owner_new"

///|
pub fn CleanupOwner::new(action : () -> Unit) -> CleanupOwner {
  let invoke : FuncRef[(() -> Unit) -> Unit] = fn(action) { action() }
  new_cleanup_owner(invoke, action)
}

///|
#borrow(self)
pub extern "c" fn CleanupOwner::close(self : CleanupOwner) -> Unit = "wasmoon_cleanup_owner_close"
