///|
/// Store-local identities retain recursive-group equivalence across modules.
priv struct StoreTypeRegistry {
  representatives : Array[(ArrayView[@types.SubType], ArrayView[Int32], Int32)]
  mappings : Map[
    Int32,
    (ArrayView[@types.SubType], ArrayView[Int32], Array[Int32]),
  ]
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
    mappings: Map([]),
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
  self.register_graph(
    instance.types,
    instance.type_rec_groups,
    instance.store_idx,
  )
}

///|
fn StoreTypeRegistry::register_graph(
  self : StoreTypeRegistry,
  types : ArrayView[@types.SubType],
  groups : ArrayView[Int32],
  store_index : Int32,
) -> Array[Int32] {
  if store_index >= 0 &&
    self.mappings.get(store_index)
    is Some((cached_types, cached_groups, mapping)) &&
    cached_types == types &&
    cached_groups == groups {
    return mapping
  }
  let mapping : Array[Int32] = []
  let first_new = self.representatives.length()
  for type_index in 0..<types.length() {
    let mut identity = -1
    for candidate, representative in self.representatives {
      let (other_types, other_groups, index) = representative
      let equivalent = @types.TypeEquivalenceContext::cross_module(
        types,
        other_types,
        rec_groups1=groups,
        rec_groups2=other_groups,
      )
      if equivalent.types_equivalent(type_index, index) {
        identity = candidate
        break
      }
    }
    if identity < 0 {
      identity = self.representatives.length()
      self.representatives.push((types, groups, type_index))
      self.parents.push(-1)
    }
    mapping.push(identity)
  }
  if store_index >= 0 {
    self.mappings.set(store_index, (types, groups, mapping))
  }
  for identity in first_new..<self.representatives.length() {
    let (_, _, index) = self.representatives[identity]
    if types[index].supertypes is [parent, ..] {
      self.parents[identity] = mapping[parent]
    }
  }
  if self.representatives.length() > first_new {
    self.publish()
  }
  mapping
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
        self.native_types.register_graph(
          self.module_types,
          self.module_rec_groups,
          -1,
        )[type_index]
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
    let (types, _, index) = self.native_types.representatives[identity]
    return Some(types[index])
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
