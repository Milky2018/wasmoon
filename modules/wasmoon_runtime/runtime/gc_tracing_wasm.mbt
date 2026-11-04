///|
priv enum NativeGcTrace {
  Disabled
}

///|
fn Store::trace_native_continuation(
  _self : Store,
  handle : Int64,
  _pending : Array[@types.Value],
  trace : GcTrace,
) -> Unit {
  // Native continuation handles cannot originate from this backend.
  if !trace.native_continuations.contains(handle) {
    trace.native_continuations.set(handle, true)
    trace.failed = true
  }
}

///|
fn Store::trace_object_fields(
  self : Store,
  index : Int32,
  pending : Array[@types.Value],
  trace : GcTrace,
) -> Unit {
  try {
    match self.heap.get(index) {
      Struct(object) =>
        for field in object.fields {
          pending.push(field)
        }
      Array(object) =>
        for element in object.elements {
          pending.push(element)
        }
    }
  } catch {
    _ => trace.failed = true
  }
}

///|
fn Store::reclaim_native_continuations(_self : Store) -> Unit {
  ()
}

///|
fn Store::release_native_exception(_self : Store, _index : Int32) -> Unit {
  ()
}

///|
fn Store::trace_table_roots(
  _self : Store,
  table : Table,
  pending : Array[@types.Value],
  trace : GcTrace,
) -> Unit {
  for index in 0..<table.size() {
    pending.push(table.root_at(index)) catch {
      _ => trace.failed = true
    }
  }
}

///|
fn Store::begin_native_gc_trace(
  _self : Store,
  young~ : Bool = false,
) -> NativeGcTrace {
  ignore(young)
  Disabled
}

///|
fn Store::trace_native_graph(
  _self : Store,
  _index : Int32,
  _pending : Array[@types.Value],
  trace : GcTrace,
) -> Bool {
  match trace.native {
    Disabled => false
  }
}

///|
fn Store::trace_objects(_self : Store, trace : GcTrace) -> Array[@types.Value] {
  trace.objects
}
