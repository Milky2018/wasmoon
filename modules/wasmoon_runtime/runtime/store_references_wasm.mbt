///|
priv enum NativeReferenceState {
  Empty
} derive(Debug)

///|
fn StoreReferences::record_exception_allocation(
  self : StoreReferences,
  index : Int32,
) -> Unit {
  self.on_instantiation_rollback(fn() {
    self.exns.remove(index)
    self.release_auxiliary_handle(1, index.to_int64())
  })
}
