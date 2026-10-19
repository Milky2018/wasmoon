///|
/// Read-only diagnostic counts; no mutable backing storage is exposed.
pub struct StoreCounts {
  funcs : Int32
  func_types : Int32
  func_type_indices : Int32
  tables : Int32
  mems : Int32
  globals : Int32
  tags : Int32
  tag_type_indices : Int32
  tag_owners : Int32
  exns : Int32
  wrapped_externs : Int32
  func_owners : Int32
  instances : Int32
  jit_tables : Int32
  heap_slots : Int32
  heap_live : Int32
  wrapped_extern_capacity : Int32
} derive(Debug)

///|
#cfg(target="native")
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
    jit_tables: self.jit_tables.length(),
    heap_slots: self.heap.length(),
    heap_live: self.heap.stats().live_objects,
    wrapped_extern_capacity: self.wrapped_externs.capacity(),
  }
}

///|
pub fn Store::get_instance(
  self : Store,
  index : Int32,
) -> ModuleInstance raise RuntimeError {
  self.ensure_open()
  guard index >= 0 && index < self.instances.length() else {
    raise InvalidHandle
  }
  self.instances[index]
}

///|
/// Native integration capability; not part of the portable embedding interface.
#cfg(target="native")
pub fn Store::native_heap(self : Store) -> @native_bridge.CHeap? {
  self.c_heap
}

///|
pub fn Store::current_types(self : Store) -> Array[@types.SubType] {
  self.module_types.copy()
}

///|
pub extend StoreCounts with Debug::{to_repr}

///|
/// Opaque Store identity. Holding this token does not keep the Store alive.
pub struct StoreIdentity {
  priv closed : Ref[Bool]
}

///|
pub fn Store::identity(self : Store) -> StoreIdentity {
  { closed: self.closed, }
}

///|
pub fn StoreIdentity::matches(self : StoreIdentity, store : Store) -> Bool {
  physical_equal(self.closed, store.closed)
}

///|
pub fn Store::is_closed(self : Store) -> Bool {
  self.closed.val
}
