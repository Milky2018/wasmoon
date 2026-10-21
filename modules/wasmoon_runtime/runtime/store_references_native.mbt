///|
priv struct ExceptionAllocationJournal {
  instances : Array[Int32]
  snapshots : Array[(Int32, Int64)]
} derive(Debug)

///|
priv struct NativeReferenceState {
  native_execution : @native_bridge.NativeExecutionState
  // One heap slot shared by Store operations and retained reference codecs.
  mut c_heap : @native_bridge.CHeap?
  // Keep payload records until resource rollback establishes surviving roots.
  mut exception_allocations : ExceptionAllocationJournal?
  native_exception_to_store : Map[Int64, Int32]
  store_exception_to_native : Map[Int32, Int64]
} derive(Debug)

///|
fn StoreReferences::record_exception_allocation(
  self : StoreReferences,
  index : Int32,
) -> Unit {
  if self.native.exception_allocations is Some(journal) {
    journal.instances.push(index)
  }
}
