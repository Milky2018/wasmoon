///|
#cfg(target="native")
fn gc_reference_type(ty : @types.ValueType) -> Bool {
  match ty {
    I32 | I64 | F32 | F64 | V128 => false
    _ => true
  }
}

///|
priv struct GcTrace {
  objects : Array[@types.Value]
  native : NativeGcTrace
  wrappers : Map[Int32, Bool]
  continuations : Map[Int64, Bool]
  native_continuations : Map[Int64, Bool]
  exceptions : Map[Int32, Bool]
  native_exceptions : Map[Int32, Bool]
  mut failed : Bool
}

///|
fn Store::trace_gc_roots(
  self : Store,
  additional : Array[@types.Value],
  native_roots~ : Array[@types.Value] = [],
  young~ : Bool = false,
) -> GcTrace {
  let trace : GcTrace = {
    objects: [],
    native: self.begin_native_gc_trace(young~),
    wrappers: Map([]),
    exceptions: Map([]),
    native_exceptions: Map([]),
    continuations: Map([]),
    native_continuations: Map([]),
    failed: false,
  }
  let pending = additional.copy()
  for value in native_roots {
    trace.push_native_root(value, pending)
  }
  for global in self.globals {
    if global.native is Some(_) {
      trace.push_native_root(global.root(), pending)
    } else {
      pending.push(global.root())
    }
  }
  for table in self.tables {
    self.trace_table_roots(table, pending, trace)
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
  let visited : Map[Int32, Bool] = Map([])
  // Walk every representation with one worklist, including cycles through
  // externalized references or exception payloads. No host recursion is needed.
  while pending.pop() is Some(value) {
    match value {
      ExternRef(handle) if handle < 0 => {
        let index = -1 - handle
        if !trace.wrappers.contains(index) &&
          self.references.wrapped_externs.get(index) is Some(inner) {
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
      ContRef(handle) => self.trace_native_continuation(handle, pending, trace)
      ExnRef(index) =>
        if !trace.exceptions.contains(index) &&
          self.references.exns.get(index) is Some(exception) {
          trace.exceptions.set(index, true)
          for payload in exception.values {
            pending.push(payload)
          }
        }
      StructRef(index) | ArrayRef(index) => {
        if self.trace_native_graph(index, pending, trace) {
          continue
        }
        if visited.contains(index) || !self.is_gc_valid(index) {
          continue
        }
        visited.set(index, true)
        trace.objects.push(value)
        self.trace_object_fields(index, pending, trace)
      }
      _ => ()
    }
  }
  trace
}

///|
#cfg(target="native")
fn Store::native_trace_roots(
  self : Store,
  trace : GcTrace,
) -> Array[Int64] raise RuntimeError {
  if trace.failed {
    raise UndefinedElement
  }
  let roots = trace.native.seeds.copy()
  roots.append(trace.objects.map(@native_bridge.value_to_i64))
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
  self.reclaim_native_continuations()
  // Snapshot candidates before cancellation callbacks can allocate new handles.
  let cancelled : Array[GuestContinuationBody] = []
  for handle in self.guest_continuations.keys().to_array() {
    if !trace.continuations.contains(handle) &&
      self.guest_continuations.get(handle) is Some(body) {
      self.guest_continuations.remove(handle)
      cancelled.push(body)
    }
  }
  for index in self.references.wrapped_externs.keys().to_array() {
    if !trace.wrappers.contains(index) {
      self.references.wrapped_externs.remove(index)
      self.release_auxiliary_handle(0, index.to_int64())
    }
  }
  for index in self.references.exns.keys().to_array() {
    if !trace.exceptions.contains(index) {
      self.references.exns.remove(index)
      self.release_auxiliary_handle(1, index.to_int64())
      self.release_native_exception(index)
    }
  }
  self.references.wrapped_externs = compact_gc_registry(
    self.references.wrapped_externs,
  )
  self.references.exns = compact_gc_registry(self.references.exns)
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
#cfg(target="native")
fn Store::decode_gc_root_words(
  self : Store,
  words : FixedArray[Int64],
) -> Array[@types.Value] raise RuntimeError {
  if words.length() == 1 && words[0] == -2L {
    raise InvalidHandle
  }
  guard self.references.native.c_heap is Some(heap) else { return [] }
  let roots : Array[@types.Value] = []
  for word in words {
    if word < 0L && (word & 1L) != 0L {
      roots.push(ContRef(word >> 1))
    } else if @native_bridge.is_exception_ref(word) {
      roots.push(self.decode_native_exception(word))
    } else if @native_bridge.decode_gc_heap_ref(word) is Some(index) {
      roots.push(
        if heap.is_array(index) {
          ArrayRef(index)
        } else {
          StructRef(index)
        },
      )
    }
  }
  roots
}

///|
#cfg(target="native")
fn Store::install_gc_tracing(self : Store) -> Unit {
  guard self.references.native.c_heap is Some(heap) else { return }
  self.native_execution.exceptions().enable_reclamation()
  heap.bind_generational_root_visitor(
    fn(phase, words) {
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
        let roots = self.decode_gc_root_words(words)
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
        if trace.native.graph is Some(graph) {
          graph.mark()
        }
        FixedArray::makei(raw.length(), i => raw[i])
      } catch {
        _ => {
          self.gc_trace = None
          [-2L]
        }
      }
    },
    fn(words) { self.trace_young_collection(words) },
  )
}

///|
#cfg(target="native")
fn Store::young_auxiliary_empty(self : Store) -> Bool {
  self.references.wrapped_externs.is_empty() &&
  self.references.exns.is_empty() &&
  self.guest_continuations.is_empty() &&
  !self.native_execution.exceptions().has_entries() &&
  !self.native_execution.continuations().has_entries()
}

///|
#cfg(target="native")
fn Store::trace_young_collection(
  self : Store,
  words : FixedArray[Int64],
) -> FixedArray[Int64]? {
  // Full discovery owns auxiliary lifetimes and explicit pre-expanded traces.
  // Declining here does not mutate marks or the guest heap.
  guard self.gc_trace is None && self.young_auxiliary_empty() else {
    return None
  }
  self.gc_in_collect = true
  try {
    let roots = self.decode_gc_root_words(words)
    let trace = self.trace_gc_roots(roots, young=true)
    // Decoding a previously unseen boundary may establish auxiliary metadata.
    if !self.young_auxiliary_empty() ||
      !trace.wrappers.is_empty() ||
      !trace.exceptions.is_empty() ||
      !trace.continuations.is_empty() ||
      !trace.native_continuations.is_empty() {
      self.gc_in_collect = false
      return None
    }
    let raw = self.native_trace_roots(trace)
    self.gc_trace = Some(trace)
    if trace.native.graph is Some(graph) {
      graph.mark()
    }
    Some(FixedArray::makei(raw.length(), i => raw[i]))
  } catch {
    _ => {
      self.gc_trace = None
      Some([-2L])
    }
  }
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
#cfg(target="native")
pub fn Store::begin_gc_tracing(self : Store) -> Unit {
  if self.gc_tracing_depth == 0 {
    self.install_gc_tracing()
  }
  self.gc_tracing_depth += 1
}

///|
/// Balance begin_gc_tracing even when native execution traps or suspends.
#cfg(target="native")
pub fn Store::end_gc_tracing(self : Store) -> Unit {
  if self.gc_tracing_depth <= 0 {
    return
  }
  self.gc_tracing_depth -= 1
  if self.gc_tracing_depth == 0 && self.references.native.c_heap is Some(heap) {
    heap.clear_root_visitor()
  }
}

///|
#cfg(target="native")
impl Debug for GcTrace with fn to_repr(_self) {
  @debug.Repr::literal("GcTrace")
}

///|
fn GcTrace::push_native_root(
  self : GcTrace,
  value : @types.Value,
  pending : Array[@types.Value],
) -> Unit {
  if value is ExnRef(index) {
    self.native_exceptions.set(index, true)
  }
  pending.push(value)
}
