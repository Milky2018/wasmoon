///|
priv struct NativeReferenceState {
  native_execution : @native_bridge.NativeExecutionState
  // One heap slot shared by Store operations and retained reference codecs.
  mut c_heap : @native_bridge.CHeap?
  native_exception_to_store : Map[Int64, Int32]
  store_exception_to_native : Map[Int32, Int64]
} derive(Debug)
