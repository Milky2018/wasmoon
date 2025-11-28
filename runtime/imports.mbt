///|
/// Function instance - either WASM code or host function
pub(all) enum FuncInst {
  /// WASM function with code
  WasmFunc(@wasmoon.FunctionCode)
  /// Host function provided by the embedder
  HostFunc((Array[@wasmoon.Value]) -> Array[@wasmoon.Value] raise RuntimeError)
}

///|
pub impl Show for FuncInst with output(self, logger) {
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
}

///|
/// Import object: maps (module_name, name) to external values
pub(all) struct Imports {
  entries : Array[(String, String, ExternVal)]
}

///|
pub fn Imports::new() -> Imports {
  { entries: [] }
}

///|
pub fn Imports::add_func(
  self : Imports,
  mod_name : String,
  name : String,
  func_addr : Int,
) -> Unit {
  self.entries.push((mod_name, name, ExternVal::Func(func_addr)))
}

///|
pub fn Imports::add_memory(
  self : Imports,
  mod_name : String,
  name : String,
  mem_addr : Int,
) -> Unit {
  self.entries.push((mod_name, name, ExternVal::Memory(mem_addr)))
}

///|
pub fn Imports::add_table(
  self : Imports,
  mod_name : String,
  name : String,
  table_addr : Int,
) -> Unit {
  self.entries.push((mod_name, name, ExternVal::Table(table_addr)))
}

///|
pub fn Imports::add_global(
  self : Imports,
  mod_name : String,
  name : String,
  global_addr : Int,
) -> Unit {
  self.entries.push((mod_name, name, ExternVal::Global(global_addr)))
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
