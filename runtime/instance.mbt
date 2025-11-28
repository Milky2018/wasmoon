///|
/// Runtime instance of a WebAssembly module
pub(all) struct ModuleInstance {
  types : Array[@types.FuncType]
  func_addrs : Array[Int] // addresses into function store
  func_type_indices : Array[Int] // type indices for each function
  table_addrs : Array[Int] // indices into table store
  mem_addrs : Array[Int] // indices into memory store
  global_addrs : Array[Int] // indices into global store
  exports : Array[@types.Export]
  elem_segments : Array[@types.Element]
  data_segments : Array[@types.Data]
} derive(Show)

///|
pub fn ModuleInstance::new() -> ModuleInstance {
  {
    types: [],
    func_addrs: [],
    func_type_indices: [],
    table_addrs: [],
    mem_addrs: [],
    global_addrs: [],
    exports: [],
    elem_segments: [],
    data_segments: [],
  }
}
