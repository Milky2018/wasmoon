///|
/// Managed callable metadata; native builds publish the same arrays to a C view.
pub struct NativeCallableView {
  priv mut parents : FixedArray[Int32]
  priv mut addresses : FixedArray[Int64]
  priv mut identities : FixedArray[Int32]
  priv mut stores : FixedArray[Int32]
  priv mut pointers : FixedArray[Int64]
  priv mut references : FixedArray[Int64]
  priv mut reference_stores : FixedArray[Int32]
} derive(Debug)

///|
pub extend NativeCallableView with Debug::{to_repr}

///|
fn new_view() -> NativeCallableView {
  {
    parents: [],
    addresses: [],
    identities: [],
    stores: [],
    pointers: [],
    references: [],
    reference_stores: [],
  }
}

///|
fn publish(
  view : NativeCallableView,
  parents : FixedArray[Int32],
  _parent_count : Int32,
  addresses : FixedArray[Int64],
  identities : FixedArray[Int32],
  _entry_count : Int32,
  _store_origin : Int32,
  _store_positions : FixedArray[Int32],
) -> Unit {
  view.parents = parents
  view.addresses = addresses
  view.identities = identities
}

///|
fn publish_functions(
  view : NativeCallableView,
  stores : FixedArray[Int32],
  pointers : FixedArray[Int64],
  _count : Int32,
  references : FixedArray[Int64],
  reference_stores : FixedArray[Int32],
  _reference_count : Int32,
  _store_origin : Int32,
  _store_positions : FixedArray[Int32],
) -> Unit {
  view.stores = stores
  view.pointers = pointers
  view.references = references
  view.reference_stores = reference_stores
}
