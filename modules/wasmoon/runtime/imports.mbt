///|
/// Function instance - either WASM code or host function
pub(all) enum FuncInst {
  /// WASM function with code
  WasmFunc(@types.FunctionCode)
  /// Host function provided by the embedder
  HostFunc(
    (Caller, Array[@types.Value]) -> Array[@types.Value] raise RuntimeError
  )
}

///|
/// Keep `Debug` support for `Store` while `FuncInst` contains non-debuggable
/// host function closures.
pub impl Debug for FuncInst with fn to_repr(self) {
  match self {
    WasmFunc(code) => Repr::ctor("WasmFunc", [(None, Repr(code))])
    HostFunc(_) => Repr::ctor("HostFunc", [(None, Repr::literal("<native>"))])
  }
}

///|
pub impl Show for FuncInst with fn output(self, logger) {
  match self {
    WasmFunc(code) => logger.write_string("WasmFunc(\{code})")
    HostFunc(_) => logger.write_string("HostFunc(<native>)")
  }
}

///|
/// External value for imports
pub(all) enum ExternVal {
  Func(Int) // function address in store
  Table(Int) // table address in store
  Memory(Int) // memory address in store
  Global(Int) // global address in store
  Tag(Int) // tag address in store (type index)
}

///|
/// Import object: maps (module_name, name) to external values
struct Imports {
  entries : Array[(String, String, ExternVal)]
}

///|
pub fn Imports::Imports() -> Imports {
  { entries: [], }
}

///|
pub fn Imports::add_func(
  self : Imports,
  mod_name : String,
  name : String,
  func_addr : Int,
) -> Unit {
  self.entries.push((mod_name, name, Func(func_addr)))
}

///|
pub fn Imports::add_memory(
  self : Imports,
  mod_name : String,
  name : String,
  mem_addr : Int,
) -> Unit {
  self.entries.push((mod_name, name, Memory(mem_addr)))
}

///|
pub fn Imports::add_table(
  self : Imports,
  mod_name : String,
  name : String,
  table_addr : Int,
) -> Unit {
  self.entries.push((mod_name, name, Table(table_addr)))
}

///|
pub fn Imports::add_global(
  self : Imports,
  mod_name : String,
  name : String,
  global_addr : Int,
) -> Unit {
  self.entries.push((mod_name, name, Global(global_addr)))
}

///|
pub fn Imports::add_tag(
  self : Imports,
  mod_name : String,
  name : String,
  tag_addr : Int,
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
