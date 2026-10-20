///|
pub fn Store::has_guest_continuation(self : Store, handle : Int64) -> Bool {
  !self.closed.val && handle >= 0L && self.guest_continuations.contains(handle)
}
