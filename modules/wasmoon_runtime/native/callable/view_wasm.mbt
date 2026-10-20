///|
/// Managed callable metadata; native builds publish the same arrays to a C view.
pub struct NativeCallableView {
  priv mut parents : FixedArray[Int32]
  priv mut addresses : FixedArray[Int64]
  priv mut identities : FixedArray[Int32]
} derive(Debug)

///|
pub extend NativeCallableView with Debug::{to_repr}

///|
fn new_view() -> NativeCallableView {
  { parents: [], addresses: [], identities: [], }
}

///|
fn publish(
  view : NativeCallableView,
  parents : FixedArray[Int32],
  _parent_count : Int32,
  addresses : FixedArray[Int64],
  identities : FixedArray[Int32],
  _entry_count : Int32,
) -> Unit {
  view.parents = parents
  view.addresses = addresses
  view.identities = identities
}
