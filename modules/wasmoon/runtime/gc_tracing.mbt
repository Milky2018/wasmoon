///|
fn gc_reference_type(ty : @types.ValueType) -> Bool {
  match ty {
    I32 | I64 | F32 | F64 | V128 => false
    _ => true
  }
}

///|
priv struct GcTrace {
  objects : Array[@types.Value]
  wrappers : Map[Int32, Bool]
  continuations : Map[Int64, Bool]
  native_continuations : Map[Int64, Bool]
  exceptions : Map[Int32, Bool]
  mut failed : Bool
} derive(Debug)

///|
fn Store::trace_gc_roots(
  self : Store,
  additional : Array[@types.Value],
) -> GcTrace {
  let pending = additional.copy()
  for global in self.globals {
    pending.push(global.root())
  }
  for table in self.tables {
    for index in 0..<table.size {
      pending.push(table.elements[index])
    }
  }
  for instance in self.instances {
    for index, values in instance.elem_values {
      if instance.dropped_elems[index] {
        values.clear()
        values.shrink_to_fit()
      } else {
        for value in values {
          pending.push(value)
        }
      }
    }
  }
  for entry in self.pinned_gc_roots.values() {
    if entry.active.val && !entry.guest_owned {
      for value in entry.values {
        pending.push(value)
      }
    }
  }
  let trace : GcTrace = {
    objects: [],
    wrappers: Map([]),
    exceptions: Map([]),
    continuations: Map([]),
    native_continuations: Map([]),
    failed: false,
  }
  let visited : Map[Int32, Bool] = Map([])
  // Walk every representation with one worklist, including cycles through
  // externalized references or exception payloads. No host recursion is needed.
  while pending.pop() is Some(value) {
    match value {
      ExternRef(handle) if handle < 0 => {
        let index = -1 - handle
        if !trace.wrappers.contains(index) &&
          self.wrapped_externs.get(index) is Some(inner) {
          trace.wrappers.set(index, true)
          pending.push(inner)
        }
      }
      ContRef(handle) if handle >= 0L =>
        if !trace.continuations.contains(handle) &&
          self.guest_continuations.get(handle) is Some(body) {
          trace.continuations.set(handle, true)
          for value in body.roots {
            pending.push(value)
          }
        }
      ContRef(handle) => {
        let reference = (handle << 1) | 1L
        if !trace.native_continuations.contains(reference) {
          trace.native_continuations.set(reference, true)
          for word in self.native_execution.continuations().gc_roots(reference) {
            if word < 0L && (word & 1L) != 0L {
              pending.push(ContRef(word >> 1))
            } else if @wasmoon_jit.is_exception_ref(word) {
              pending.push(self.decode_native_exception(word)) catch {
                _ => trace.failed = true
              }
            } else if @wasmoon_jit.decode_gc_heap_ref(word) is Some(child) {
              pending.push(
                if self.c_heap is Some(heap) && heap.is_array(child) {
                  ArrayRef(child)
                } else {
                  StructRef(child)
                },
              )
            }
          }
        }
      }
      ExnRef(index) =>
        if !trace.exceptions.contains(index) &&
          self.exns.get(index) is Some(exception) {
          trace.exceptions.set(index, true)
          for payload in exception.values {
            pending.push(payload)
          }
        }
      StructRef(index) | ArrayRef(index) => {
        if visited.contains(index) || !self.is_gc_valid(index) {
          continue
        }
        visited.set(index, true)
        trace.objects.push(value)
        match self.c_heap {
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
                    pending.push(self.struct_get(index, field)) catch {
                      _ => trace.failed = true
                    }
                  }
                }
              Some({ composite: Array(definition), .. }) =>
                if definition.element.storage_type is Val(ty) &&
                  gc_reference_type(ty) {
                  for element in 0..<heap.array_len(index) {
                    pending.push(self.array_get(index, element)) catch {
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
                  } else if @wasmoon_jit.is_exception_ref(word) {
                    pending.push(self.decode_native_exception(word)) catch {
                      _ => trace.failed = true
                    }
                  } else if @wasmoon_jit.decode_gc_heap_ref(word) is Some(child) {
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
      _ => ()
    }
  }
  trace
}

///|
fn Store::native_trace_roots(
  self : Store,
  trace : GcTrace,
) -> Array[Int64] raise RuntimeError {
  if trace.failed {
    raise UndefinedElement
  }
  let roots = trace.objects.map(@wasmoon_jit.value_to_i64)
  for index in trace.exceptions.keys() {
    roots.push(self.encode_native_exception(index))
  }
  for reference in trace.native_continuations.keys() {
    roots.push(reference)
  }
  roots
}

///|
fn Store::release_unreachable_handles(self : Store, trace : GcTrace) -> Unit {
  self.native_execution.continuations().reclaim_retired()
  // Snapshot candidates before cancellation callbacks can allocate new handles.
  let cancelled : Array[GuestContinuationBody] = []
  for handle in self.guest_continuations.keys().to_array() {
    if !trace.continuations.contains(handle) &&
      self.guest_continuations.get(handle) is Some(body) {
      self.guest_continuations.remove(handle)
      cancelled.push(body)
    }
  }
  for index in self.wrapped_externs.keys().to_array() {
    if !trace.wrappers.contains(index) {
      self.wrapped_externs.remove(index)
      self.auxiliary_leases.remove((0, index.to_int64()))
    }
  }
  for index in self.exns.keys().to_array() {
    if !trace.exceptions.contains(index) {
      self.exns.remove(index)
      self.auxiliary_leases.remove((1, index.to_int64()))
      if self.store_exception_to_native.get(index) is Some(reference) {
        self.native_execution.exceptions().release_snapshot(reference)
        self.store_exception_to_native.remove(index)
        self.native_exception_to_store.remove(reference)
      }
    }
  }
  self.wrapped_externs = compact_gc_registry(self.wrapped_externs)
  self.exns = compact_gc_registry(self.exns)
  self.guest_continuations = compact_gc_registry(self.guest_continuations)
  self.pinned_gc_roots = compact_gc_registry(self.pinned_gc_roots)
  for body in cancelled {
    (body.cancel)()
  }
  for index in self.native_types.heap_types.keys().to_array() {
    if !self.is_gc_valid(index) {
      self.native_types.heap_types.remove(index)
    }
  }
}

///|
fn Store::install_gc_tracing(self : Store) -> Unit {
  guard self.c_heap is Some(heap) else { return }
  self.native_execution.exceptions().enable_reclamation()
  heap.bind_root_visitor(fn(phase, words) {
    if phase == 2 {
      self.gc_trace = None
      self.gc_in_collect = false
      return []
    }
    if phase == 1 {
      if self.gc_trace is Some(trace) {
        self.release_unreachable_handles(trace)
      }
      self.gc_trace = None
      self.gc_in_collect = false
      return []
    }
    self.gc_in_collect = true
    try {
      let roots : Array[@types.Value] = []
      for word in words {
        if word < 0L && (word & 1L) != 0L {
          roots.push(ContRef(word >> 1))
        } else if @wasmoon_jit.is_exception_ref(word) {
          roots.push(self.decode_native_exception(word))
        } else if @wasmoon_jit.decode_gc_heap_ref(word) is Some(index) {
          roots.push(
            if heap.is_array(index) {
              ArrayRef(index)
            } else {
              StructRef(index)
            },
          )
        }
      }
      // Explicit host roots were already expanded before entering native GC.
      if self.gc_trace is Some(trace) {
        for index in trace.wrappers.keys() {
          roots.push(ExternRef(-1 - index))
        }
        for index in trace.exceptions.keys() {
          roots.push(ExnRef(index))
        }
        for handle in trace.continuations.keys() {
          roots.push(ContRef(handle))
        }
      }
      let trace = self.trace_gc_roots(roots)
      self.gc_trace = Some(trace)
      let raw = self.native_trace_roots(trace)
      FixedArray::makei(raw.length(), i => raw[i])
    } catch {
      _ => {
        self.gc_trace = None
        [-2L]
      }
    }
  })
}

///|
fn gc_root_key(value : @types.Value) -> (Int32, Int64)? {
  match value {
    StructRef(index) => Some((0, index.to_int64()))
    ArrayRef(index) => Some((1, index.to_int64()))
    ExternRef(index) if index < 0 => Some((2, index.to_int64()))
    ExnRef(index) => Some((3, index.to_int64()))
    ContRef(index) => Some((4, index))
    _ => None
  }
}

///|
fn[K, V] compact_gc_registry(registry : Map[K, V]) -> Map[K, V] {
  if registry.capacity() > 16 &&
    registry.capacity().to_int64() > registry.length().to_int64() * 4L {
    registry.filter((_, _) => true)
  } else {
    registry
  }
}

///|
/// Install the Store visitor only while native execution or a collection needs
/// it. A permanent native closure would create a Store/heap reference cycle.
pub fn Store::begin_gc_tracing(self : Store) -> Unit {
  if self.gc_tracing_depth == 0 {
    self.install_gc_tracing()
  }
  self.gc_tracing_depth += 1
}

///|
/// Balance begin_gc_tracing even when native execution traps or suspends.
pub fn Store::end_gc_tracing(self : Store) -> Unit {
  if self.gc_tracing_depth <= 0 {
    return
  }
  self.gc_tracing_depth -= 1
  if self.gc_tracing_depth == 0 && self.c_heap is Some(heap) {
    heap.clear_root_visitor()
  }
}
