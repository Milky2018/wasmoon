///|
/// Function instance - either WASM code or host function
pub(all) enum FuncInst {
  /// WASM function with code
  WasmFunc(@types.FunctionCode)
  /// Host function provided by the embedder
  HostFunc(
    (Caller, Array[@types.Value]) -> Array[@types.Value] raise RuntimeError
  )
  /// Asynchronous host function provided by the embedder.
  AsyncHostFunc(AsyncHostFunction)
}

///|
/// Keep `Debug` support for `Store` while `FuncInst` contains non-debuggable
/// host function closures.
pub impl Debug for FuncInst with fn to_repr(self) {
  match self {
    WasmFunc(code) => Repr::ctor("WasmFunc", [(None, Repr(code))])
    HostFunc(_) => Repr::ctor("HostFunc", [(None, Repr::literal("<native>"))])
    AsyncHostFunc(_) =>
      Repr::ctor("AsyncHostFunc", [(None, Repr::literal("<async-native>"))])
  }
}

///|
pub impl Show for FuncInst with fn output(self, logger) {
  match self {
    WasmFunc(code) => logger.write_string("WasmFunc(\{code})")
    HostFunc(_) => logger.write_string("HostFunc(<native>)")
    AsyncHostFunc(_) => logger.write_string("AsyncHostFunc(<async-native>)")
  }
}

///|
/// External value for imports
pub(all) enum ExternVal {
  Func(Int32) // function address in store
  Table(Int32) // table address in store
  Memory(Int32) // memory address in store
  Global(Int32) // global address in store
  Tag(Int32) // tag address in store (type index)
}

///|
/// Import object: maps (module_name, name) to external values
struct Imports {
  owner : Store
  entries : Array[(String, String, ExternVal)]
}

///|
pub fn Imports::Imports(store : Store) -> Imports {
  { entries: [], owner: store, }
}

///|
pub fn Imports::add_func(
  self : Imports,
  mod_name : String,
  name : String,
  func_addr : Int32,
) -> Unit {
  self.entries.push((mod_name, name, Func(func_addr)))
}

///|
pub fn Imports::add_memory(
  self : Imports,
  mod_name : String,
  name : String,
  mem_addr : Int32,
) -> Unit {
  self.entries.push((mod_name, name, Memory(mem_addr)))
}

///|
pub fn Imports::add_table(
  self : Imports,
  mod_name : String,
  name : String,
  table_addr : Int32,
) -> Unit {
  self.entries.push((mod_name, name, Table(table_addr)))
}

///|
pub fn Imports::add_global(
  self : Imports,
  mod_name : String,
  name : String,
  global_addr : Int32,
) -> Unit {
  self.entries.push((mod_name, name, Global(global_addr)))
}

///|
pub fn Imports::add_tag(
  self : Imports,
  mod_name : String,
  name : String,
  tag_addr : Int32,
) -> Unit {
  self.entries.push((mod_name, name, Tag(tag_addr)))
}

///|
pub fn Imports::resolve(
  self : Imports,
  mod_name : String,
  name : String,
) -> ExternVal? {
  for entry in self.entries {
    let (m, n, v) = entry
    if m == mod_name && n == name {
      return Some(v)
    }
  }
  None
}

///|
pub fn Imports::check_store(
  self : Imports,
  store : Store,
) -> Unit raise RuntimeError {
  store.ensure_open()
  guard physical_equal(self.owner, store) else { raise ForeignStore }
}
