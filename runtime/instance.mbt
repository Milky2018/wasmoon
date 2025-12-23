///|
/// Runtime instance of a WebAssembly module
pub(all) struct ModuleInstance {
  types : Array[@types.SubType] // GC: now stores SubType
  type_rec_groups : Array[Int] // rec group IDs for each type
  canonical_type_indices : Array[Int] // canonical indices for structural equivalence
  mut store_idx : Int // index in the store's instances array, -1 if not registered
  func_addrs : Array[Int] // addresses into function store
  func_type_indices : Array[Int] // type indices for each function
  table_addrs : Array[Int] // indices into table store
  mem_addrs : Array[Int] // indices into memory store
  global_addrs : Array[Int] // indices into global store
  tag_addrs : Array[Int] // indices into tag store
  exports : Array[@types.Export]
  elem_segments : Array[@types.Element]
  data_segments : Array[@types.Data]
  dropped_elems : Array[Bool] // true if elem segment has been dropped
  dropped_datas : Array[Bool] // true if data segment has been dropped
} derive(Show)

///|
pub fn ModuleInstance::new() -> ModuleInstance {
  {
    types: [],
    type_rec_groups: [],
    canonical_type_indices: [],
    store_idx: -1,
    func_addrs: [],
    func_type_indices: [],
    table_addrs: [],
    mem_addrs: [],
    global_addrs: [],
    tag_addrs: [],
    exports: [],
    elem_segments: [],
    data_segments: [],
    dropped_elems: [],
    dropped_datas: [],
  }
}

///|
/// Get the function type at the given index.
/// Panics if the type is not a function type.
pub fn ModuleInstance::get_func_type(
  self : ModuleInstance,
  idx : Int,
) -> @types.FuncType {
  match self.types[idx].composite {
    Func(ft) => ft
    _ => abort("Type at index \{idx} is not a function type")
  }
}

///|
/// Get the struct type at the given index.
/// Panics if the type is not a struct type.
pub fn ModuleInstance::get_struct_type(
  self : ModuleInstance,
  idx : Int,
) -> @types.StructType {
  match self.types[idx].composite {
    Struct(st) => st
    _ => abort("Type at index \{idx} is not a struct type")
  }
}

///|
/// Get the array type at the given index.
/// Panics if the type is not an array type.
pub fn ModuleInstance::get_array_type(
  self : ModuleInstance,
  idx : Int,
) -> @types.ArrayType {
  match self.types[idx].composite {
    Array(at) => at
    _ => abort("Type at index \{idx} is not an array type")
  }
}
