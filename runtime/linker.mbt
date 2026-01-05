///|
/// Linker for managing multiple module instances and their dependencies
struct Linker {
  store : Store
  modules : Array[(String, ModuleInstance)] // (name, instance) pairs
}

///|
/// Create a new linker with a fresh store
pub fn Linker::new() -> Linker {
  { store: Store::new(), modules: [] }
}

///|
/// Create a new linker with an existing store
pub fn Linker::with_store(store : Store) -> Linker {
  { store, modules: [] }
}

///|
/// Get the underlying store
pub fn Linker::get_store(self : Linker) -> Store {
  self.store
}

///|
/// Register a module instance with a name
/// The module's exports will be available as imports for subsequent modules
pub fn Linker::register(
  self : Linker,
  name : String,
  instance : ModuleInstance,
) -> Unit {
  self.modules.push((name, instance))
}

///|
/// Build Imports from all registered modules
/// This allows a new module to import from any previously registered module
pub fn Linker::build_imports(self : Linker) -> Imports {
  let imports = Imports::new()
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
/// Add a host function to the linker
/// This function will be available as an import for all subsequently instantiated modules
pub fn Linker::add_host_func(
  self : Linker,
  mod_name : String,
  name : String,
  func : (Array[@types.Value]) -> Array[@types.Value] raise RuntimeError,
  func_type? : @types.FuncType = { params: [], results: [] },
) -> Unit {
  let func_addr = self.store.alloc_host_func(func, func_type~)
  // Create a minimal instance to hold this function
  // We need to add it to an existing module or create a synthetic one
  // For simplicity, we add directly to the imports when building
  // by storing it in a separate structure
  // Actually, we need to store it somewhere accessible
  // Let's add a host_funcs field to store these
  // For now, we'll use a workaround by creating a synthetic module entry

  // Find or create a module entry for this mod_name
  fn find_or_create_host_module(
    modules : Array[(String, ModuleInstance)],
    target_name : String,
  ) -> Int {
    for i, entry in modules {
      let (name, _) = entry
      if name == target_name {
        return i
      }
    }
    // Create new synthetic module
    let instance : ModuleInstance = {
      types: [],
      type_rec_groups: [],
      canonical_type_indices: [],
      store_idx: -1,
      func_addrs: [],
      func_type_indices: [],
      table_addrs: [],
      mem_addrs: [],
      global_addrs: [],
      tag_addrs: [],
      exports: [],
      elem_segments: [],
      data_segments: [],
      dropped_elems: [],
      dropped_datas: [],
    }
    modules.push((target_name, instance))
    modules.length() - 1
  }

  let idx = find_or_create_host_module(self.modules, mod_name)
  let (_, instance) = self.modules[idx]
  instance.func_addrs.push(func_addr)
  instance.exports.push({
    name,
    desc: @types.ExportDesc::Func(instance.func_addrs.length() - 1),
  })
}

///|
/// Add a memory to the linker
pub fn Linker::add_memory(
  self : Linker,
  mod_name : String,
  name : String,
  mem : Memory,
) -> Unit {
  let mem_addr = self.store.alloc_mem(mem)
  fn find_or_create_host_module(
    modules : Array[(String, ModuleInstance)],
    target_name : String,
  ) -> Int {
    for i, entry in modules {
      let (n, _) = entry
      if n == target_name {
        return i
      }
    }
    let instance : ModuleInstance = {
      types: [],
      type_rec_groups: [],
      canonical_type_indices: [],
      store_idx: -1,
      func_addrs: [],
      func_type_indices: [],
      table_addrs: [],
      mem_addrs: [],
      global_addrs: [],
      tag_addrs: [],
      exports: [],
      elem_segments: [],
      data_segments: [],
      dropped_elems: [],
      dropped_datas: [],
    }
    modules.push((target_name, instance))
    modules.length() - 1
  }

  let idx = find_or_create_host_module(self.modules, mod_name)
  let (_, instance) = self.modules[idx]
  instance.mem_addrs.push(mem_addr)
  instance.exports.push({
    name,
    desc: @types.ExportDesc::Memory(instance.mem_addrs.length() - 1),
  })
}

///|
/// Add a table to the linker
pub fn Linker::add_table(
  self : Linker,
  mod_name : String,
  name : String,
  table : Table,
) -> Unit {
  let table_addr = self.store.alloc_table(table)
  fn find_or_create_host_module(
    modules : Array[(String, ModuleInstance)],
    target_name : String,
  ) -> Int {
    for i, entry in modules {
      let (n, _) = entry
      if n == target_name {
        return i
      }
    }
    let instance : ModuleInstance = {
      types: [],
      type_rec_groups: [],
      canonical_type_indices: [],
      store_idx: -1,
      func_addrs: [],
      func_type_indices: [],
      table_addrs: [],
      mem_addrs: [],
      global_addrs: [],
      tag_addrs: [],
      exports: [],
      elem_segments: [],
      data_segments: [],
      dropped_elems: [],
      dropped_datas: [],
    }
    modules.push((target_name, instance))
    modules.length() - 1
  }

  let idx = find_or_create_host_module(self.modules, mod_name)
  let (_, instance) = self.modules[idx]
  instance.table_addrs.push(table_addr)
  instance.exports.push({
    name,
    desc: @types.ExportDesc::Table(instance.table_addrs.length() - 1),
  })
}

///|
/// Add a global to the linker
pub fn Linker::add_global(
  self : Linker,
  mod_name : String,
  name : String,
  global : GlobalInstance,
) -> Unit {
  let global_addr = self.store.alloc_global(global)
  fn find_or_create_host_module(
    modules : Array[(String, ModuleInstance)],
    target_name : String,
  ) -> Int {
    for i, entry in modules {
      let (n, _) = entry
      if n == target_name {
        return i
      }
    }
    let instance : ModuleInstance = {
      types: [],
      type_rec_groups: [],
      canonical_type_indices: [],
      store_idx: -1,
      func_addrs: [],
      func_type_indices: [],
      table_addrs: [],
      mem_addrs: [],
      global_addrs: [],
      tag_addrs: [],
      exports: [],
      elem_segments: [],
      data_segments: [],
      dropped_elems: [],
      dropped_datas: [],
    }
    modules.push((target_name, instance))
    modules.length() - 1
  }

  let idx = find_or_create_host_module(self.modules, mod_name)
  let (_, instance) = self.modules[idx]
  instance.global_addrs.push(global_addr)
  instance.exports.push({
    name,
    desc: @types.ExportDesc::Global(instance.global_addrs.length() - 1),
  })
}
