///|
/// Linker for managing multiple module instances and their dependencies
struct Linker {
  store : Store
  modules : Array[(String, ModuleInstance)] // (name, instance) pairs
}

///|
/// Create a new linker with a fresh store
pub fn Linker::Linker() -> Linker raise RuntimeError {
  { store: Store(), modules: [], }
}

///|
/// Create a new linker with an existing store
pub fn Linker::with_store(store : Store) -> Linker {
  { store, modules: [], }
}

///|
/// Get the underlying store
pub fn Linker::get_store(self : Linker) -> Store {
  self.store
}

///|
/// Register rollback for core allocations and names added by an instantiation.
pub fn Linker::register_rollback(
  self : Linker,
  registrar : RollbackRegistrar,
) -> Unit {
  self.store.register_rollback(registrar)
}

///|
fn Linker::host_module(
  self : Linker,
  name : String,
) -> (ModuleInstance, Int32) raise RuntimeError {
  let modules = self.modules.length()
  for entry in self.modules {
    let (module_name, instance) = entry
    if module_name == name {
      return (instance, modules)
    }
  }
  let instance = self.store.host_exports([])
  self.modules.push((name, instance))
  (instance, modules)
}

///|
fn Linker::rollback_module_change(
  self : Linker,
  modules : Int32,
  rollback : () -> Unit,
) -> Unit {
  self.store.on_instantiation_rollback(fn() {
    rollback()
    self.modules.truncate(modules)
  })
}

///|
/// Release this linker's store after all module execution has ended.
///
/// This operation is idempotent and terminal.
pub fn Linker::close(self : Linker) -> Unit {
  self.modules.clear()
  self.modules.shrink_to_fit()
  self.store.close()
}

///|
/// Register a module instance with a name
/// The module's exports will be available as imports for subsequent modules
pub fn Linker::register(
  self : Linker,
  name : String,
  instance : ModuleInstance,
) -> Unit raise RuntimeError {
  self.store.check_instance(instance)
  let modules = self.modules.length()
  self.store.on_instantiation_rollback(fn() { self.modules.truncate(modules) })
  self.modules.push((name, instance))
}

///|
/// Build Imports from all registered modules
/// This allows a new module to import from any previously registered module
pub fn Linker::build_imports(self : Linker) -> Imports {
  let imports = Imports::Imports(self.store)
  for entry in self.modules {
    let (mod_name, instance) = entry
    for exp in instance.exports {
      match exp.desc {
        Func(idx) => {
          let func_addr = instance.func_addrs[idx]
          imports.add_func(mod_name, exp.name, func_addr)
        }
        Table(idx) => {
          let table_addr = instance.table_addrs[idx]
          imports.add_table(mod_name, exp.name, table_addr)
        }
        Memory(idx) => {
          let mem_addr = instance.mem_addrs[idx]
          imports.add_memory(mod_name, exp.name, mem_addr)
        }
        Global(idx) => {
          let global_addr = instance.global_addrs[idx]
          imports.add_global(mod_name, exp.name, global_addr)
        }
        Tag(idx) => {
          let tag_addr = instance.tag_addrs[idx]
          imports.add_tag(mod_name, exp.name, tag_addr)
        }
      }
    }
  }
  imports
}

///|
/// Get a registered module instance by name
pub fn Linker::get_module(self : Linker, name : String) -> ModuleInstance? {
  for entry in self.modules {
    let (mod_name, instance) = entry
    if mod_name == name {
      return Some(instance)
    }
  }
  None
}

///|
fn Linker::add_func_export(
  self : Linker,
  mod_name : String,
  name : String,
  func_addr : Int32,
) -> Unit raise RuntimeError {
  let (instance, modules) = self.host_module(mod_name)
  let func_addrs = instance.func_addrs
  let exports = instance.exports
  self.rollback_module_change(modules, fn() {
    instance.func_addrs = func_addrs
    instance.exports = exports
  })
  instance.func_addrs = append_readonly(instance.func_addrs, func_addr)
  instance.exports = append_readonly(instance.exports, {
    name,
    desc: Func(instance.func_addrs.length() - 1),
  })
}

///|
/// Add a host function to the linker
/// This function will be available as an import for all subsequently instantiated modules
pub fn Linker::add_host_func(
  self : Linker,
  mod_name : String,
  name : String,
  func : (Array[@types.Value]) -> Array[@types.Value] raise RuntimeError,
  func_type~ : @types.FuncType = { params: [], results: [], },
) -> Unit raise RuntimeError {
  self.store.ensure_open()
  let func_addr = self.store.alloc_host_func(func, func_type~)
  self.add_func_export(mod_name, name, func_addr)
}

///|
/// Add a host function that receives the caller context.
pub fn Linker::add_host_func_with_caller(
  self : Linker,
  mod_name : String,
  name : String,
  func : (Caller, Array[@types.Value]) -> Array[@types.Value] raise RuntimeError,
  func_type~ : @types.FuncType = { params: [], results: [], },
) -> Unit raise RuntimeError {
  self.store.ensure_open()
  let func_addr = self.store.alloc_host_func_with_caller(func, func_type~)
  self.add_func_export(mod_name, name, func_addr)
}

///|
/// Add an asynchronous host function to the linker.
///
/// The function can only be invoked through an asynchronous Wasm call. Its
/// future is polled while the Wasm continuation is parked.
pub fn Linker::add_async_host_func(
  self : Linker,
  mod_name : String,
  name : String,
  func : async (Array[@types.Value]) -> Array[@types.Value] raise Error,
  func_type~ : @types.FuncType = { params: [], results: [], },
) -> Unit raise RuntimeError {
  self.store.ensure_open()
  let func_addr = self.store.alloc_async_host_func(func, func_type~)
  self.add_func_export(mod_name, name, func_addr)
}

///|
/// Add an asynchronous host function that receives the caller context.
pub fn Linker::add_async_host_func_with_caller(
  self : Linker,
  mod_name : String,
  name : String,
  func : async (Caller, Array[@types.Value]) -> Array[@types.Value] raise Error,
  func_type~ : @types.FuncType = { params: [], results: [], },
) -> Unit raise RuntimeError {
  self.store.ensure_open()
  let func_addr = self.store.alloc_async_host_func_with_caller(func, func_type~)
  self.add_func_export(mod_name, name, func_addr)
}

///|
/// Add a memory to the linker
pub fn Linker::add_memory(
  self : Linker,
  mod_name : String,
  name : String,
  mem : Memory,
) -> Unit raise RuntimeError {
  self.store.ensure_open()
  let mem_addr = self.store.alloc_mem(mem)
  let (instance, modules) = self.host_module(mod_name)
  let mem_addrs = instance.mem_addrs
  let exports = instance.exports
  self.rollback_module_change(modules, fn() {
    instance.mem_addrs = mem_addrs
    instance.exports = exports
  })
  instance.mem_addrs = append_readonly(instance.mem_addrs, mem_addr)
  instance.exports = append_readonly(instance.exports, {
    name,
    desc: Memory(instance.mem_addrs.length() - 1),
  })
}

///|
/// Add a table to the linker
pub fn Linker::add_table(
  self : Linker,
  mod_name : String,
  name : String,
  table : Table,
) -> Unit raise RuntimeError {
  self.store.ensure_open()
  let table_addr = self.store.alloc_table(table)
  let (instance, modules) = self.host_module(mod_name)
  let table_addrs = instance.table_addrs
  let exports = instance.exports
  self.rollback_module_change(modules, fn() {
    instance.table_addrs = table_addrs
    instance.exports = exports
  })
  instance.table_addrs = append_readonly(instance.table_addrs, table_addr)
  instance.exports = append_readonly(instance.exports, {
    name,
    desc: Table(instance.table_addrs.length() - 1),
  })
}

///|
/// Add a global to the linker
pub fn Linker::add_global(
  self : Linker,
  mod_name : String,
  name : String,
  global : GlobalInstance,
) -> Unit raise RuntimeError {
  self.store.ensure_open()
  let global_addr = self.store.alloc_global(global)
  let (instance, modules) = self.host_module(mod_name)
  let global_addrs = instance.global_addrs
  let exports = instance.exports
  self.rollback_module_change(modules, fn() {
    instance.global_addrs = global_addrs
    instance.exports = exports
  })
  instance.global_addrs = append_readonly(instance.global_addrs, global_addr)
  instance.exports = append_readonly(instance.exports, {
    name,
    desc: Global(instance.global_addrs.length() - 1),
  })
}

///|
fn[T] append_readonly(values : ReadOnlyArray[T], value : T) -> ReadOnlyArray[T] {
  ReadOnlyArray::makei(values.length() + 1, i => {
    if i < values.length() {
      values[i]
    } else {
      value
    }
  })
}
