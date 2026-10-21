///|
#cfg(target="native")
fn gc_storage_code(storage : @types.StorageType) -> Int32 {
  match storage {
    Packed(I8) => 1
    Packed(I16) => 2
    Val(I32 | F32) => 4
    Val(I64 | F64) => 8
    Val(V128) => 16
    Val(
      ContRef
      | RefCont
      | RefContTyped(_)
      | RefNullContTyped(_)
      | NullContRef
      | RefNoCont
    ) => -9
    Val(_) => -8
  }
}

///|
#cfg(target="native")
fn Store::prepare_native_gc_layouts(self : Store) -> Bool {
  guard self.references.native.c_heap is Some(heap) else { return true }
  let registry = self.native_types
  while registry.native_layout_count < registry.representatives.length() {
    let identity = registry.native_layout_count
    let (graph, index) = registry.representatives[identity]
    let (fields, array) = match graph.types[index].composite {
      Struct(definition) =>
        (
          definition.fields.map(field => gc_storage_code(field.storage_type)),
          false,
        )
      Array(definition) =>
        ([gc_storage_code(definition.element.storage_type)], true)
      _ => {
        registry.native_layout_count += 1
        continue
      }
    }
    if !heap
      .get_ptr()
      .define_layout(
        identity,
        FixedArray::makei(fields.length(), i => fields[i]),
        array,
      ) {
      return false
    }
    registry.native_layout_count += 1
  }
  true
}

///|
#cfg(target="native")
fn Store::allocation_type(
  self : Store,
  instance : ModuleInstance?,
  type_index : Int32,
  array~ : Bool = false,
) -> Int32 {
  let indices = match instance {
    Some(instance) => self.native_types.register(instance)
    None => self.module_type_indices()
  }
  guard type_index >= 0 && type_index < indices.length() else { return -1 }
  let identity = indices[type_index]
  let (graph, index) = self.native_types.representatives[identity]
  match (array, graph.types[index].composite) {
    (false, Struct(_)) | (true, Array(_)) => ()
    _ => return -1
  }
  if !self.prepare_native_gc_layouts() {
    return -1
  }
  identity
}
