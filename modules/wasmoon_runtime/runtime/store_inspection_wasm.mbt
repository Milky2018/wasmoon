///|
pub fn Store::counts(self : Store) -> StoreCounts {
  {
    funcs: self.funcs.length(),
    func_types: self.func_types.length(),
    func_type_indices: self.func_type_indices.length(),
    tables: self.tables.length(),
    mems: self.mems.length(),
    globals: self.globals.length(),
    tags: self.tags.length(),
    tag_type_indices: self.tag_type_indices.length(),
    tag_owners: self.tag_owners.length(),
    exns: self.exns.length(),
    wrapped_externs: self.wrapped_externs.length(),
    func_owners: self.func_owners.length(),
    instances: self.instances.length(),
    jit_tables: 0,
    heap_slots: self.heap.length(),
    heap_live: self.heap.stats().live_objects,
    wrapped_extern_capacity: self.wrapped_externs.capacity(),
  }
}
