///|
/// Store-local identities retain recursive-group equivalence across modules.
priv struct RegisteredTypeGraph {
  id : Int64
  types : ArrayView[@types.SubType]
  groups : ArrayView[Int32]
  mapping : Array[Int32]
} derive(Debug)

///|
priv struct RegisteredInstanceTypes {
  instance : ModuleInstance
  graph : RegisteredTypeGraph
} derive(Debug)

///|
priv struct StoreTypeRegistry {
  representatives : Array[(RegisteredTypeGraph, Int32)]
  group_buckets : Map[Int64, Array[(RegisteredTypeGraph, Array[Int32])]]
  mappings : Map[Int32, RegisteredInstanceTypes]
  mut initialization_graph : RegisteredTypeGraph?
  mut next_graph_id : Int64
  parents : Array[Int32]
  views : Array[NativeCallableTypeView]
  mut native_registry : @native_bridge.NativeCallableRegistry?
  entries : Map[Int64, Int32]
  heap_types : Map[Int32, Int32]
} derive(Debug)

///|
fn StoreTypeRegistry::new() -> StoreTypeRegistry {
  {
    representatives: [],
    group_buckets: Map([]),
    mappings: Map([]),
    initialization_graph: None,
    next_graph_id: 0L,
    parents: [],
    views: [],
    native_registry: None,
    entries: Map([]),
    heap_types: Map([]),
  }
}

///|
fn StoreTypeRegistry::register(
  self : StoreTypeRegistry,
  instance : ModuleInstance,
) -> Array[Int32] {
  if self.mappings.get(instance.store_idx) is Some(cached) &&
    physical_equal(cached.instance, instance) {
    return cached.graph.mapping
  }
  // These snapshots are immutable. Compare them only when a new live instance
  // adopts the initialization graph, never on an already registered lookup.
  if self.initialization_graph is Some(graph) &&
    graph.types == instance.types &&
    graph.groups == instance.type_rec_groups {
    self.mappings[instance.store_idx] = { instance, graph, }
    return graph.mapping
  }
  self.register_graph(instance.types, instance.type_rec_groups, Some(instance)).mapping
}

///|
fn StoreTypeRegistry::register_graph(
  self : StoreTypeRegistry,
  types : ArrayView[@types.SubType],
  groups : ArrayView[Int32],
  instance : ModuleInstance?,
) -> RegisteredTypeGraph {
  let mapping = Array::make(types.length(), -1)
  let graph = { id: self.next_graph_id, types, groups, mapping, }
  self.next_graph_id += 1L
  // Reuse graph indices and completed equivalence results within this registration.
  // These contexts must not outlive the two immutable graphs they compare.
  let comparisons : Map[Int64, @types.TypeEquivalenceContext] = Map([])
  let first_new = self.representatives.length()
  @types.fold_type_groups(
    types,
    type_rec_groups=groups,
    external_identity=fn(index) {
      if index < mapping.length() {
        mapping[index]
      } else {
        -1
      }
    },
    visit=fn(members, fingerprint) {
      let candidates = self.group_buckets.get_or_default(fingerprint, [])
      let mut matched = false
      for (other, previous) in candidates {
        let equivalent = match comparisons.get(other.id) {
          Some(context) => context
          None => {
            let context = @types.TypeEquivalenceContext::cross_module(
              types,
              other.types,
              rec_groups1=groups,
              rec_groups2=other.groups,
            )
            comparisons[other.id] = context
            context
          }
        }
        if equivalent.types_equivalent(members[0], previous[0]) {
          for position, index in members {
            mapping[index] = other.mapping[previous[position]]
          }
          matched = true
          break
        }
      }
      if !matched {
        for index in members {
          mapping[index] = self.representatives.length()
          self.representatives.push((graph, index))
          self.parents.push(-1)
        }
        candidates.push((graph, members.to_owned()))
        self.group_buckets[fingerprint] = candidates
      }
    },
  )
  // Install ownership before publication: a refresh callback may reenter,
  // replace the initialization scope, roll back, or close the Store.
  match instance {
    Some(instance) => self.mappings[instance.store_idx] = { instance, graph, }
    None => self.initialization_graph = Some(graph)
  }
  for identity in first_new..<self.representatives.length() {
    let (_, index) = self.representatives[identity]
    if types[index].supertypes is [parent, ..] {
      self.parents[identity] = mapping[parent]
    }
  }
  if self.representatives.length() > first_new {
    self.publish()
  }
  graph
}

///|
pub fn Store::native_type_indices(
  self : Store,
  instance : ModuleInstance,
) -> Array[Int32] {
  self.check_instance(instance) catch {
    _ => return []
  }
  self.native_types.register(instance).copy()
}

///|
pub fn Store::native_type_parents(self : Store) -> Array[Int32] {
  self.native_types.parents.copy()
}

///|
priv struct NativeCallableTypeView {
  refresh : (Array[Int32], Array[(Int64, Int32)]) -> Unit
}

///|
impl Debug for NativeCallableTypeView with fn to_repr(_self) {
  Repr::literal("NativeCallableTypeView")
}

///|
/// Publish the complete Store type universe to all installed callable contexts.
pub fn Store::bind_native_callable_view(
  self : Store,
  refresh : (Array[Int32], Array[(Int64, Int32)]) -> Unit,
) -> Unit {
  self.native_types.views.push({ refresh, })
  for entry in self.jit_funcref_entries() {
    self.native_types.entries[entry.func_ptr] = self.get_func_canonical_type_idx(
      entry.store_addr,
    )
  }
  self.native_types.publish()
}

///|
/// Share Store-wide callable identities while each context owns its local maps.
/// Returns None after the Store is closed.
pub fn Store::native_callable_registry(
  self : Store,
) -> @native_bridge.NativeCallableRegistry? {
  guard !self.closed.val else { return None }
  let mut changed = false
  let registry = match self.native_types.native_registry {
    Some(registry) => registry
    None => {
      changed = true
      let registry = @native_bridge.NativeCallableRegistry::new()
      self.native_types.native_registry = Some(registry)
      registry
    }
  }
  if self.funcref_registry.native is None {
    self.funcref_registry.native = Some(registry)
    self.funcref_registry.publish_functions()
  }
  for entry in self.jit_funcref_entries() {
    let identity = self.get_func_canonical_type_idx(entry.store_addr)
    if self.native_types.entries.get(entry.func_ptr) != Some(identity) {
      self.native_types.entries[entry.func_ptr] = identity
      changed = true
    }
  }
  if changed {
    self.native_types.publish()
  }
  Some(registry)
}

///|
#cfg(target="native")
fn Store::record_gc_type(
  self : Store,
  index : Int32,
  instance : ModuleInstance?,
  type_index : Int32,
) -> Unit {
  let identity = match instance {
    Some(instance) => self.native_types.register(instance)[type_index]
    None =>
      if type_index >= 0 && type_index < self.module_types.length() {
        self.module_type_indices()[type_index]
      } else {
        -1
      }
  }
  match self.c_heap {
    Some(heap) => heap.set_runtime_type(index, identity)
    None => self.native_types.heap_types[index] = identity
  }
}

///|
#cfg(target="native")
pub fn Store::gc_type_is_subtype(
  self : Store,
  reference : Int32,
  instance : ModuleInstance,
  expected : Int32,
) -> Bool {
  self.check_instance(instance) catch {
    _ => return false
  }
  guard expected >= 0 && expected < instance.types.length() else {
    return false
  }
  let actual = match self.c_heap {
    Some(heap) => heap.runtime_type(reference)
    None => self.native_types.heap_types.get(reference).unwrap_or(-1)
  }
  if actual < 0 {
    let local_index = self.get_gc_type_idx(reference) catch {
      _ => return false
    }
    return @types.SubtypingContext::same_module(
      instance.types,
      rec_groups=instance.type_rec_groups,
    ).is_subtype(local_index, expected)
  }
  let target = self.native_types.register(instance)[expected]
  self.native_types.is_subtype(actual, target)
}

///|
fn StoreTypeRegistry::is_subtype(
  self : StoreTypeRegistry,
  actual : Int32,
  expected : Int32,
) -> Bool {
  for current = actual; current >= 0 && current < self.parents.length(); {
    if current == expected {
      return true
    }
    let parent = self.parents[current]
    if parent == current {
      return false
    }
    continue parent
  }
  false
}

///|
#cfg(target="native")
fn Store::gc_type_definition(
  self : Store,
  reference : Int32,
  fallback : Int32,
) -> @types.SubType? {
  let identity = match self.c_heap {
    Some(heap) => heap.runtime_type(reference)
    None => self.native_types.heap_types.get(reference).unwrap_or(-1)
  }
  if identity >= 0 && identity < self.native_types.representatives.length() {
    let (graph, index) = self.native_types.representatives[identity]
    return Some(graph.types[index])
  }
  if fallback >= 0 && fallback < self.module_types.length() {
    Some(self.module_types[fallback])
  } else {
    None
  }
}

///|
fn StoreTypeRegistry::publish(self : StoreTypeRegistry) -> Unit {
  if self.native_registry is None && self.views.is_empty() {
    return
  }
  let entries : Array[(Int64, Int32)] = []
  for pointer, identity in self.entries {
    entries.push((pointer, identity))
  }
  if self.native_registry is Some(registry) {
    if !registry.replace(self.parents, entries) {
      abort("failed to publish native callable identities")
    }
  }
  if self.views.is_empty() {
    return
  }
  for view in self.views {
    (view.refresh)(self.parents.copy(), entries.copy())
  }
}

///|
pub fn Store::func_type_is_subtype(
  self : Store,
  address : Int32,
  instance : ModuleInstance,
  expected : Int32,
) -> Bool {
  self.check_instance(instance) catch {
    _ => return false
  }
  guard expected >= 0 && expected < instance.types.length() else {
    return false
  }
  let actual = self.get_func_canonical_type_idx(address)
  if actual < 0 {
    return false
  }
  self.native_types.is_subtype(
    actual,
    self.native_types.register(instance)[expected],
  )
}

///|
fn Store::module_type_indices(self : Store) -> Array[Int32] {
  if self.native_types.initialization_graph is Some(graph) {
    return graph.mapping
  }
  let graph = self.native_types.register_graph(
    self.module_types,
    self.module_rec_groups,
    None,
  )
  graph.mapping
}
