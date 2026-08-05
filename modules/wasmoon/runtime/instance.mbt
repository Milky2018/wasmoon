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
} derive(Debug)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for ModuleInstance with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
pub fn ModuleInstance::ModuleInstance() -> ModuleInstance {
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

// Type-kind lookups on an instance.
//
// An instance exists only after its module passed validation, so a type
// index used as a function type names one. That is a claim about wasmoon,
// not about the input, and the names now say so: `validated_` marks every
// caller that leans on validation having run (ISS-396).
//
// The bounds check is not redundant with that claim. Reaching it means an
// index arrived from somewhere validation does not cover, and saying so
// beats dying on an array access with nothing on either stream.

///|
/// The function type at `idx`, in an instance whose module passed validation.
pub fn ModuleInstance::validated_func_type_at(
  self : ModuleInstance,
  idx : Int,
) -> @types.FuncType {
  guard idx >= 0 && idx < self.types.length() else {
    abort("validated instance has no type at index \{idx}")
  }
  match self.types[idx].composite {
    Func(ft) => ft
    _ => abort("validated instance has no function type at index \{idx}")
  }
}

///|
/// The struct type at `idx`, in an instance whose module passed validation.
pub fn ModuleInstance::validated_struct_type_at(
  self : ModuleInstance,
  idx : Int,
) -> @types.StructType {
  guard idx >= 0 && idx < self.types.length() else {
    abort("validated instance has no type at index \{idx}")
  }
  match self.types[idx].composite {
    Struct(st) => st
    _ => abort("validated instance has no struct type at index \{idx}")
  }
}

///|
/// The array type at `idx`, in an instance whose module passed validation.
pub fn ModuleInstance::validated_array_type_at(
  self : ModuleInstance,
  idx : Int,
) -> @types.ArrayType {
  guard idx >= 0 && idx < self.types.length() else {
    abort("validated instance has no type at index \{idx}")
  }
  match self.types[idx].composite {
    Array(at) => at
    _ => abort("validated instance has no array type at index \{idx}")
  }
}
