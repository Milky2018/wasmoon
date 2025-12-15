///|
/// The store contains all global runtime state
pub struct Store {
  funcs : Array[FuncInst]
  func_types : Array[@types.FuncType] // Type of each function
  tables : Array[Table]
  mems : Array[Memory]
  globals : Array[GlobalInstance]
  // Maps function address to its owning module instance address
  // Used for cross-module call context switching
  func_owners : Array[Int] // -1 means host function or not yet registered
  // Registered module instances by their address/index
  instances : Array[ModuleInstance]
  // JIT tables corresponding to runtime tables (for cross-module sharing)
  // jit_tables[i] is the JIT table for tables[i], or None if not using JIT
  jit_tables : Array[@jit.JITTable?]
} derive(Show)

///|
pub fn Store::new() -> Store {
  {
    funcs: [],
    func_types: [],
    tables: [],
    mems: [],
    globals: [],
    func_owners: [],
    instances: [],
    jit_tables: [],
  }
}

///|
/// Allocate a WASM function with its type
pub fn Store::alloc_func(
  self : Store,
  func : @types.FunctionCode,
  func_type? : @types.FuncType = { params: [], results: [] },
) -> Int {
  let idx = self.funcs.length()
  self.funcs.push(FuncInst::WasmFunc(func))
  self.func_types.push(func_type)
  self.func_owners.push(-1) // Owner not yet known
  idx
}

///|
/// Allocate a host function with its type
pub fn Store::alloc_host_func(
  self : Store,
  func : (Array[@types.Value]) -> Array[@types.Value] raise RuntimeError,
  func_type? : @types.FuncType = { params: [], results: [] },
) -> Int {
  let idx = self.funcs.length()
  self.funcs.push(FuncInst::HostFunc(func))
  self.func_types.push(func_type)
  self.func_owners.push(-1) // Host functions don't have an owner
  idx
}

///|
/// Allocate a table in the store
/// Always creates a corresponding JIT table for cross-module sharing
pub fn Store::alloc_table(
  self : Store,
  table : Table,
  use_jit? : Bool = true,
) -> Int {
  let idx = self.tables.length()
  self.tables.push(table)

  // Create corresponding JIT table (always enabled for cross-module sharing)
  if use_jit {
    let (min, max) = table.get_limits()
    let jit_table = @jit.JITTable::new(min, max)
    self.jit_tables.push(jit_table)
  } else {
    self.jit_tables.push(None)
  }
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
/// Get function type by store address
pub fn Store::get_func_type(
  self : Store,
  idx : Int,
) -> @types.FuncType raise RuntimeError {
  if idx < 0 || idx >= self.func_types.length() {
    raise UndefinedElement
  }
  self.func_types[idx]
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
/// Get the JIT table corresponding to a runtime table (if exists)
pub fn Store::get_jit_table(self : Store, idx : Int) -> @jit.JITTable? {
  if idx < 0 || idx >= self.jit_tables.length() {
    return None
  }
  self.jit_tables[idx]
}

///|
pub fn Store::get_mem(self : Store, idx : Int) -> Memory raise RuntimeError {
  if idx < 0 || idx >= self.mems.length() {
    raise UndefinedElement
  }
  self.mems[idx]
}

///|
/// Get memory by index (returns None if not found)
/// This is useful for WASI functions that need memory access
pub fn Store::get_memory(self : Store, idx : Int) -> Memory {
  if idx < 0 || idx >= self.mems.length() {
    // Return a dummy empty memory if not found
    Memory::new(0, None)
  } else {
    self.mems[idx]
  }
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
