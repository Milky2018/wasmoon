///|
fn Store::trace_native_continuation(
  self : Store,
  handle : Int64,
  pending : Array[@types.Value],
  trace : GcTrace,
) -> Unit {
  let reference = (handle << 1) | 1L
  if !trace.native_continuations.contains(reference) {
    trace.native_continuations.set(reference, true)
    for word in self.native_execution.continuations().gc_roots(reference) {
      if word < 0L && (word & 1L) != 0L {
        pending.push(ContRef(word >> 1))
      } else if @native_bridge.is_exception_ref(word) {
        trace.push_native_root(self.decode_native_exception(word), pending) catch {
          _ => trace.failed = true
        }
      } else if @native_bridge.decode_gc_heap_ref(word) is Some(child) {
        pending.push(
          if self.references.native.c_heap is Some(heap) && heap.is_array(child) {
            ArrayRef(child)
          } else {
            StructRef(child)
          },
        )
      }
    }
  }
}

///|
fn Store::trace_object_fields(
  self : Store,
  index : Int32,
  pending : Array[@types.Value],
  trace : GcTrace,
) -> Unit {
  match self.references.native.c_heap {
    None =>
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
    Some(heap) => {
      let local_type = heap.get_type_idx(index)
      match self.gc_type_definition(index, local_type) {
        Some({ composite: Struct(definition), .. }) =>
          for field, definition in definition.fields {
            if definition.storage_type is Val(ty) && gc_reference_type(ty) {
              trace.push_native_root(self.struct_get(index, field), pending) catch {
                _ => trace.failed = true
              }
            }
          }
        Some({ composite: Array(definition), .. }) =>
          if definition.element.storage_type is Val(ty) && gc_reference_type(ty) {
            for element in 0..<heap.array_len(index) {
              trace.push_native_root(self.array_get(index, element), pending) catch {
                _ => trace.failed = true
              }
            }
          }
        _ =>
          // Untyped low-level allocations keep the conservative raw-word
          // contract. Validated module objects use their declared fields.
          for word in heap.reference_candidates(index) {
            if word < 0L && (word & 1L) != 0L {
              pending.push(ContRef(word >> 1))
            } else if @native_bridge.is_exception_ref(word) {
              trace.push_native_root(
                self.decode_native_exception(word),
                pending,
              ) catch {
                _ => trace.failed = true
              }
            } else if @native_bridge.decode_gc_heap_ref(word) is Some(child) {
              pending.push(
                if heap.is_array(child) {
                  ArrayRef(child)
                } else {
                  StructRef(child)
                },
              )
            }
          }
      }
    }
  }
}

///|
fn Store::reclaim_native_continuations(self : Store) -> Unit {
  self.native_execution.continuations().reclaim_retired()
}

///|
fn Store::release_native_exception(self : Store, index : Int32) -> Unit {
  self.references.release_native_exception(index)
}

///|
fn Store::trace_table_roots(
  _self : Store,
  table : Table,
  pending : Array[@types.Value],
  trace : GcTrace,
) -> Unit {
  for index in 0..<table.size() {
    try {
      let value = table.root_at(index)
      match table.storage {
        Native(_) => trace.push_native_root(value, pending)
        Managed(_) => pending.push(value)
      }
    } catch {
      _ => trace.failed = true
    }
  }
}
