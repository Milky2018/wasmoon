///|
/// Define an immutable Store-canonical layout. Codes are scalar byte widths;
/// -8 denotes a reference word; -9 a continuation word. Unknown low-level types retain wide slots.
#borrow(self, fields)
pub extern "c" fn GCHeapHandle::define_layout(
  self : GCHeapHandle,
  identity : Int32,
  fields : FixedArray[Int32],
  array : Bool,
) -> Bool = "wasmoon_gc_heap_define_layout"

///|
#borrow(self, words)
pub extern "c" fn GCHeapHandle::allocate_typed(
  self : GCHeapHandle,
  identity : Int32,
  local_type : Int32,
  words : FixedArray[Int64],
  count : Int32,
  repeated : Bool,
) -> Int32 = "wasmoon_gc_heap_alloc_typed"

///|
pub type NativeGcTraceHandle

///|
#borrow(self)
pub extern "c" fn GCHeapHandle::begin_trace(
  self : GCHeapHandle,
) -> NativeGcTraceHandle = "wasmoon_gc_heap_begin_trace"

///|
/// Read-only graph expansion: [0, boundary (word, kind) pairs...].
/// -1 denotes an untyped seed; -2 denotes incomplete discovery.
#borrow(self)
pub extern "c" fn NativeGcTraceHandle::expand(
  self : NativeGcTraceHandle,
  reference : Int32,
) -> FixedArray[Int64] = "wasmoon_gc_heap_trace_graph"

///|
/// Materialize transitive identities only for the public collect_roots API.
#borrow(self)
pub extern "c" fn NativeGcTraceHandle::objects(
  self : NativeGcTraceHandle,
) -> FixedArray[Int64] = "wasmoon_gc_trace_objects"

///|
/// Mark a completed closure within the collector protocol; expansion itself
/// never changes collector marks, including when queried during rollback.
#borrow(self)
pub extern "c" fn NativeGcTraceHandle::mark(self : NativeGcTraceHandle) -> Unit = "wasmoon_gc_trace_mark"
