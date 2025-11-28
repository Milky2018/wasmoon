///|
/// The store contains all global runtime state
pub struct Store {
  funcs : Array[FuncInst]
  tables : Array[Table]
  mems : Array[Memory]
  globals : Array[GlobalInstance]
  // Maps function address to its owning module instance address
  // Used for cross-module call context switching
  func_owners : Array[Int] // -1 means host function or not yet registered
  // Registered module instances by their address/index
  instances : Array[ModuleInstance]
} derive(Show)

///|
pub fn Store::new() -> Store {
  {
    funcs: [],
    tables: [],
    mems: [],
    globals: [],
    func_owners: [],
    instances: [],
  }
}

///|
/// Allocate a WASM function
pub fn Store::alloc_func(self : Store, func : @types.FunctionCode) -> Int {
  let idx = self.funcs.length()
  self.funcs.push(FuncInst::WasmFunc(func))
  self.func_owners.push(-1) // Owner not yet known
  idx
}

///|
/// Allocate a host function
pub fn Store::alloc_host_func(
  self : Store,
  func : (Array[@types.Value]) -> Array[@types.Value] raise RuntimeError,
) -> Int {
  let idx = self.funcs.length()
  self.funcs.push(FuncInst::HostFunc(func))
  self.func_owners.push(-1) // Host functions don't have an owner
  idx
}

///|
pub fn Store::alloc_table(self : Store, table : Table) -> Int {
  let idx = self.tables.length()
  self.tables.push(table)
  idx
}

///|
pub fn Store::alloc_mem(self : Store, mem : Memory) -> Int {
  let idx = self.mems.length()
  self.mems.push(mem)
  idx
}

///|
pub fn Store::alloc_global(self : Store, global : GlobalInstance) -> Int {
  let idx = self.globals.length()
  self.globals.push(global)
  idx
}

///|
pub fn Store::get_func_inst(
  self : Store,
  idx : Int,
) -> FuncInst raise RuntimeError {
  if idx < 0 || idx >= self.funcs.length() {
    raise UndefinedElement
  }
  self.funcs[idx]
}

///|
/// Get WASM function code (for backward compatibility)
pub fn Store::get_func(
  self : Store,
  idx : Int,
) -> @types.FunctionCode raise RuntimeError {
  match self.get_func_inst(idx) {
    WasmFunc(code) => code
    HostFunc(_) => raise TypeMismatch // Cannot get code from host function
  }
}

///|
pub fn Store::get_table(self : Store, idx : Int) -> Table raise RuntimeError {
  if idx < 0 || idx >= self.tables.length() {
    raise UndefinedElement
  }
  self.tables[idx]
}

///|
pub fn Store::get_mem(self : Store, idx : Int) -> Memory raise RuntimeError {
  if idx < 0 || idx >= self.mems.length() {
    raise UndefinedElement
  }
  self.mems[idx]
}

///|
pub fn Store::get_global(
  self : Store,
  idx : Int,
) -> GlobalInstance raise RuntimeError {
  if idx < 0 || idx >= self.globals.length() {
    raise UndefinedElement
  }
  self.globals[idx]
}

///|
/// Register a module instance and set ownership for its functions
/// Only sets ownership for functions that don't already have an owner
/// (imported functions already belong to their original module)
pub fn Store::register_instance(self : Store, instance : ModuleInstance) -> Int {
  let instance_idx = self.instances.length()
  self.instances.push(instance)
  // Set ownership only for functions that don't have an owner yet
  // Imported functions will already have their owner set
  for func_addr in instance.func_addrs {
    if func_addr >= 0 && func_addr < self.func_owners.length() {
      // Only set if not already owned (-1 means unowned)
      if self.func_owners[func_addr] < 0 {
        self.func_owners[func_addr] = instance_idx
      }
    }
  }
  instance_idx
}

///|
/// Get the owning module instance for a function address
pub fn Store::get_func_owner(self : Store, func_addr : Int) -> ModuleInstance? {
  if func_addr < 0 || func_addr >= self.func_owners.length() {
    return None
  }
  let owner_idx = self.func_owners[func_addr]
  if owner_idx < 0 || owner_idx >= self.instances.length() {
    return None
  }
  Some(self.instances[owner_idx])
}
