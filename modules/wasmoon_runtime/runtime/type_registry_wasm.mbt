///|
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
  self.native_types.heap_types[index] = identity
}

///|
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
  let actual = self.native_types.heap_types.get(reference).unwrap_or(-1)
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
