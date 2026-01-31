///|
/// Caller context for host functions.
///
/// This mirrors Wasmtime's `Caller` concept at a simpler level:
/// - `store` gives access to runtime state (memories, tables, globals, etc.).
/// - `instance` is the wasm module instance that called into the host.
pub struct Caller {
  store : Store
  instance : ModuleInstance
} derive(Show)

///|
pub fn Caller::new(store : Store, instance : ModuleInstance) -> Caller {
  { store, instance }
}

///|
pub fn Caller::store(self : Caller) -> Store {
  self.store
}

///|
pub fn Caller::instance(self : Caller) -> ModuleInstance {
  self.instance
}

///|
fn Caller::find_export_desc(self : Caller, name : String) -> @types.ExportDesc? {
  for exp in self.instance.exports {
    if exp.name == name {
      return Some(exp.desc)
    }
  }
  None
}

///|
/// Look up an exported memory from the caller instance.
pub fn Caller::get_exported_memory(
  self : Caller,
  name : String,
) -> Memory? raise RuntimeError {
  match self.find_export_desc(name) {
    Some(@types.ExportDesc::Memory(mem_idx)) => {
      if mem_idx < 0 || mem_idx >= self.instance.mem_addrs.length() {
        return None
      }
      let mem_addr = self.instance.mem_addrs[mem_idx]
      Some(self.store.get_mem(mem_addr))
    }
    _ => None
  }
}

///|
/// Look up an exported function address from the caller instance.
pub fn Caller::get_exported_func_addr(self : Caller, name : String) -> Int? {
  match self.find_export_desc(name) {
    Some(@types.ExportDesc::Func(func_idx)) => {
      if func_idx < 0 || func_idx >= self.instance.func_addrs.length() {
        return None
      }
      Some(self.instance.func_addrs[func_idx])
    }
    _ => None
  }
}
