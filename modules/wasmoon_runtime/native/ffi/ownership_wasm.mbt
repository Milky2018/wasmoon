///|
/// Logical accounting for one wasm-hosted interpreter. No native allocation is retained.
pub struct Quota {
  priv limit : Int64
  priv mut charged : Int64
}

///|
pub fn Quota::new(limit : Int64) -> Quota {
  { limit, charged: 0L, }
}

///|
pub fn Quota::used(self : Quota) -> Int64 {
  self.charged
}

///|
pub struct Reservation {
  priv quota : Quota
  priv mut amount : Int64
  priv mut active : Bool
}

///|
pub fn Reservation::new(quota : Quota, amount : Int64) -> Reservation {
  let active = amount >= 0L && amount <= quota.limit - quota.charged
  if active {
    quota.charged += amount
  }
  { quota, amount: if active { amount } else { 0L }, active, }
}

///|
pub fn Reservation::valid(self : Reservation) -> Bool {
  self.active
}

///|
pub fn Reservation::resize(self : Reservation, amount : Int64) -> Bool {
  if !self.active || amount < 0L {
    return false
  }
  let delta = amount - self.amount
  if delta > 0L && delta > self.quota.limit - self.quota.charged {
    return false
  }
  self.quota.charged += delta
  self.amount = amount
  true
}

///|
pub fn Reservation::close(self : Reservation) -> Unit {
  if self.active {
    self.active = false
    self.quota.charged -= self.amount
    self.amount = 0L
  }
}

///|
pub fn Reservation::matches(self : Reservation, quota : Quota) -> Bool {
  self.active && physical_equal(self.quota, quota)
}

///|
pub struct CleanupOwner {
  priv mut action : (() -> Unit)?
}

///|
pub fn CleanupOwner::new(action : () -> Unit) -> CleanupOwner {
  { action: Some(action), }
}

///|
pub fn CleanupOwner::close(self : CleanupOwner) -> Unit {
  if self.action is Some(action) {
    self.action = None
    action()
  }
}

///|
pub impl Debug for Quota with fn to_repr(self) {
  Repr::record({ "used": Repr(self.used()) })
}

///|
pub impl Debug for Reservation with fn to_repr(self) {
  Repr::literal(
    if self.active {
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

///|
// The native declarations share this import for their typed value callbacks.
let _native_value_import : Unit = ignore(@types.ONE_MIB_BYTES)
