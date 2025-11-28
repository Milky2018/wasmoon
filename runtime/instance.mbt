///|
/// Runtime instance of a WebAssembly module
pub(all) struct ModuleInstance {
  types : Array[@wasmoon.FuncType]
  func_addrs : Array[Int] // indices into function store
  table_addrs : Array[Int] // indices into table store
  mem_addrs : Array[Int] // indices into memory store
  global_addrs : Array[Int] // indices into global store
  exports : Array[@wasmoon.Export]
  elem_segments : Array[@wasmoon.Element]
  data_segments : Array[@wasmoon.Data]
} derive(Show)

///|
pub fn ModuleInstance::new() -> ModuleInstance {
  {
    types: [],
    func_addrs: [],
    table_addrs: [],
    mem_addrs: [],
    global_addrs: [],
    exports: [],
    elem_segments: [],
    data_segments: [],
  }
}
