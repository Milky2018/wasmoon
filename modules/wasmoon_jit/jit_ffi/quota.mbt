///|
/// Native atomic accounting primitive. The embedding layer owns policy and units.
pub type Quota

///|
pub extern "c" fn Quota::new(limit : Int64) -> Quota = "wasmoon_quota_new"

///|
#borrow(self)
pub extern "c" fn Quota::used(self : Quota) -> Int64 = "wasmoon_quota_used"

///|
pub impl Debug for Quota with fn to_repr(self) {
  Repr::record({ "used": Repr(self.used()) })
}

///|
/// An RC-owned reservation; its last reference returns the units to its quota.
pub type Reservation

///|
#borrow(quota)
pub extern "c" fn Reservation::new(
  quota : Quota,
  amount : Int64,
) -> Reservation = "wasmoon_reservation_new"

///|
#borrow(self)
pub extern "c" fn Reservation::valid(self : Reservation) -> Bool = "wasmoon_reservation_valid"

///|
#borrow(self)
pub extern "c" fn Reservation::resize(
  self : Reservation,
  amount : Int64,
) -> Bool = "wasmoon_reservation_resize"

///|
#borrow(self)
pub extern "c" fn Reservation::close(self : Reservation) -> Unit = "wasmoon_reservation_close"

///|
#borrow(self, quota)
pub extern "c" fn Reservation::matches(
  self : Reservation,
  quota : Quota,
) -> Bool = "wasmoon_reservation_matches"

///|
pub impl Debug for Reservation with fn to_repr(self) {
  Repr::literal(
    if self.valid() {
      "Reservation(active)"
    } else {
      "Reservation(closed)"
    },
  )
}

///|
pub extend Quota with Debug::{to_repr}

///|
pub extend Reservation with Debug::{to_repr}
