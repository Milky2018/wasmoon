///|
/// Store-local identities retain recursive-group equivalence across modules.
priv struct StoreTypeRegistry {
  representatives : Array[(ModuleInstance, Int)]
  mappings : Map[Int, (Array[@types.SubType], Array[Int], Array[Int])]
  parents : Array[Int]
  views : Array[NativeCallableTypeView]
  entries : Map[Int64, Int]
  heap_types : Map[Int, Int]
} derive(Debug)

///|
fn StoreTypeRegistry::new() -> StoreTypeRegistry {
  {
    representatives: [],
    mappings: Map([]),
    parents: [],
    views: [],
    entries: Map([]),
    heap_types: Map([]),
  }
}

///|
fn StoreTypeRegistry::register(
  self : StoreTypeRegistry,
  instance : ModuleInstance,
) -> Array[Int] {
  if instance.store_idx >= 0 &&
    self.mappings.get(instance.store_idx) is Some((types, groups, mapping)) &&
    types == instance.types &&
    groups == instance.type_rec_groups {
    return mapping
  }
  let mapping : Array[Int] = []
  let first_new = self.representatives.length()
  for type_index in 0..<instance.types.length() {
    let mut identity = -1
    for candidate, representative in self.representatives {
      let (owner, index) = representative
      let equivalent = @types.TypeEquivalenceContext::cross_module(
        instance.types,
        owner.types,
        rec_groups1=instance.type_rec_groups,
        rec_groups2=owner.type_rec_groups,
      )
      if equivalent.types_equivalent(type_index, index) {
        identity = candidate
        break
      }
    }
    if identity < 0 {
      identity = self.representatives.length()
      self.representatives.push((instance, type_index))
      self.parents.push(-1)
    }
    mapping.push(identity)
  }
  if instance.store_idx >= 0 {
    self.mappings.set(
      instance.store_idx,
      (instance.types, instance.type_rec_groups, mapping),
    )
  }
  for identity in first_new..<self.representatives.length() {
    let (_, index) = self.representatives[identity]
    if instance.types[index].supertypes is [parent, ..] {
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
) -> Array[Int] {
  self.native_types.register(instance).copy()
}

///|
pub fn Store::native_type_parents(self : Store) -> Array[Int] {
  self.native_types.parents.copy()
}

///|
priv struct NativeCallableTypeView {
  refresh : (Array[Int], Array[(Int64, Int)]) -> Unit
}

///|
impl Debug for NativeCallableTypeView with fn to_repr(_self) {
  Repr::literal("NativeCallableTypeView")
}

///|
/// Publish the complete Store type universe to all installed callable contexts.
pub fn Store::bind_native_callable_view(
  self : Store,
  refresh : (Array[Int], Array[(Int64, Int)]) -> Unit,
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
fn Store::record_gc_type(
  self : Store,
  index : Int,
  instance : ModuleInstance?,
  type_index : Int,
) -> Unit {
  let identity = match instance {
    Some(instance) => self.native_types.register(instance)[type_index]
    None => -1
  }
  match self.c_heap {
    Some(heap) => heap.set_runtime_type(index, identity)
    None => self.native_types.heap_types[index] = identity
  }
}

///|
pub fn Store::gc_type_is_subtype(
  self : Store,
  reference : Int,
  instance : ModuleInstance,
  expected : Int,
) -> Bool {
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
  actual : Int,
  expected : Int,
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
fn Store::gc_type_definition(
  self : Store,
  reference : Int,
  fallback : Int,
) -> @types.SubType? {
  let identity = match self.c_heap {
    Some(heap) => heap.runtime_type(reference)
    None => self.native_types.heap_types.get(reference).unwrap_or(-1)
  }
  if identity >= 0 && identity < self.native_types.representatives.length() {
    let (instance, index) = self.native_types.representatives[identity]
    return Some(instance.types[index])
  }
  if fallback >= 0 && fallback < self.module_types.length() {
    Some(self.module_types[fallback])
  } else {
    None
  }
}

///|
fn StoreTypeRegistry::publish(self : StoreTypeRegistry) -> Unit {
  let entries : Array[(Int64, Int)] = []
  for pointer, identity in self.entries {
    entries.push((pointer, identity))
  }
  let parents = self.parents.copy()
  for view in self.views {
    (view.refresh)(parents, entries)
  }
}
