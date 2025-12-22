///|
/// Exception instance - represents a caught exception
pub(all) struct ExnInstance {
  tag_addr : Int // Which tag was thrown
  values : Array[@types.Value] // Exception values
} derive(Show)

///|
/// Represents the ownership status of a function in the store
pub(all) enum FuncOwner {
  HostFunc // Host function - never has an owner module
  Unowned // WASM function not yet assigned to a module
  Module(Int) // WASM function owned by module at given index
} derive(Show, Eq)

///|
/// The store contains all global runtime state
pub struct Store {
  funcs : Array[FuncInst]
  func_types : Array[@types.FuncType] // Type of each function
  func_type_indices : Array[Int] // Original type index for structural comparison
  tables : Array[Table]
  mems : Array[Memory]
  globals : Array[GlobalInstance]
  tags : Array[@types.FuncType] // Tag types (params only, no results)
  exns : Array[ExnInstance] // Exception instances for exnref
  // Maps function address to its owning module instance
  // Used for cross-module call context switching
  func_owners : Array[FuncOwner]
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
    func_type_indices: [],
    tables: [],
    mems: [],
    globals: [],
    tags: [],
    exns: [],
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
  type_idx? : Int = -1,
) -> Int {
  let idx = self.funcs.length()
  self.funcs.push(FuncInst::WasmFunc(func))
  self.func_types.push(func_type)
  self.func_type_indices.push(type_idx)
  self.func_owners.push(FuncOwner::Unowned)
  idx
}

///|
/// Allocate a host function with its type
pub fn Store::alloc_host_func(
  self : Store,
  func : (Array[@types.Value]) -> Array[@types.Value] raise RuntimeError,
  func_type? : @types.FuncType = { params: [], results: [] },
  type_idx? : Int = -1,
) -> Int {
  let idx = self.funcs.length()
  self.funcs.push(FuncInst::HostFunc(func))
  self.func_types.push(func_type)
  self.func_type_indices.push(type_idx)
  self.func_owners.push(FuncOwner::HostFunc)
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
/// Allocate a tag with its type (params from FuncType, results ignored)
pub fn Store::alloc_tag(self : Store, tag_type : @types.FuncType) -> Int {
  let idx = self.tags.length()
  self.tags.push(tag_type)
  idx
}

///|
pub fn Store::get_tag_type(
  self : Store,
  idx : Int,
) -> @types.FuncType raise RuntimeError {
  if idx < 0 || idx >= self.tags.length() {
    raise UndefinedElement
  }
  self.tags[idx]
}

///|
/// Allocate an exception instance and return its index
pub fn Store::alloc_exn(
  self : Store,
  tag_addr : Int,
  values : Array[@types.Value],
) -> Int {
  let idx = self.exns.length()
  self.exns.push({ tag_addr, values })
  idx
}

///|
/// Get an exception instance by index
pub fn Store::get_exn(
  self : Store,
  idx : Int,
) -> ExnInstance raise RuntimeError {
  if idx < 0 || idx >= self.exns.length() {
    raise UndefinedElement
  }
  self.exns[idx]
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
/// Get function type index by store address (for structural comparison)
pub fn Store::get_func_type_idx(self : Store, idx : Int) -> Int {
  if idx < 0 || idx >= self.func_type_indices.length() {
    -1
  } else {
    self.func_type_indices[idx]
  }
}

///|
/// Get canonical type index for a function by store address
/// Returns the canonical type index from the function's owning module
/// Returns -1 if the function or owner is not found
pub fn Store::get_func_canonical_type_idx(self : Store, func_addr : Int) -> Int {
  if func_addr < 0 || func_addr >= self.func_owners.length() {
    return -1
  }
  let owner_idx = match self.func_owners[func_addr] {
    Module(idx) => idx
    _ => return -1
  }
  if owner_idx >= self.instances.length() {
    return -1
  }
  let instance = self.instances[owner_idx]
  let type_idx = self.func_type_indices[func_addr]
  if type_idx < 0 || type_idx >= instance.canonical_type_indices.length() {
    return -1
  }
  instance.canonical_type_indices[type_idx]
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
  instance.store_idx = instance_idx
  self.instances.push(instance)
  // Set ownership only for unowned WASM functions
  // HostFunc and already-owned functions are not changed
  for func_addr in instance.func_addrs {
    if func_addr >= 0 && func_addr < self.func_owners.length() {
      if self.func_owners[func_addr] == FuncOwner::Unowned {
        self.func_owners[func_addr] = FuncOwner::Module(instance_idx)
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
  match self.func_owners[func_addr] {
    Module(idx) =>
      if idx < self.instances.length() {
        Some(self.instances[idx])
      } else {
        None
      }
    _ => None
  }
}

///|
/// Get the owning module instance index for a function address
/// Returns -1 if no owner (host function or unowned)
pub fn Store::get_func_owner_idx(self : Store, func_addr : Int) -> Int {
  if func_addr < 0 || func_addr >= self.func_owners.length() {
    return -1
  }
  match self.func_owners[func_addr] {
    Module(idx) => idx
    _ => -1
  }
}
