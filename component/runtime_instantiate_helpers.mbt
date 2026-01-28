///|
fn resolve_sortidx(
  sortidx : SortIdx,
  state : BuildState,
) -> ComponentExtern raise ComponentRuntimeError {
  let idx = sortidx.idx
  match sortidx.sort {
    Sort::Func =>
      if idx < 0 || idx >= state.funcs.length() {
        raise InvalidFuncIndex(idx)
      } else {
        ComponentExtern::Func(state.funcs[idx])
      }
    Sort::Value =>
      if idx < 0 || idx >= state.values.length() {
        raise InvalidValueIndex(idx)
      } else {
        ComponentExtern::Value(state.values[idx])
      }
    Sort::Type =>
      if idx < 0 || idx >= state.types.length() {
        raise InvalidTypeIndex(idx)
      } else {
        ComponentExtern::Type(state.types[idx])
      }
    Sort::Component =>
      if idx < 0 || idx >= state.components.length() {
        raise InvalidComponentIndex(idx)
      } else {
        ComponentExtern::Component(state.components[idx])
      }
    Sort::Instance =>
      if idx < 0 || idx >= state.instances.length() {
        raise InvalidInstanceIndex(idx)
      } else {
        ComponentExtern::Instance(state.instances[idx])
      }
    Sort::Core(core_sort) =>
      match core_sort {
        0x00 =>
          if idx < 0 || idx >= state.core_funcs.length() {
            raise InvalidCoreFuncIndex(idx)
          } else {
            ComponentExtern::CoreFunc(state.core_funcs[idx])
          }
        0x01 =>
          if idx < 0 || idx >= state.core_tables.length() {
            raise InvalidCoreTableIndex(idx)
          } else {
            ComponentExtern::CoreTable(state.core_tables[idx])
          }
        0x02 =>
          if idx < 0 || idx >= state.core_mems.length() {
            raise InvalidCoreMemoryIndex(idx)
          } else {
            ComponentExtern::CoreMemory(state.core_mems[idx])
          }
        0x03 =>
          if idx < 0 || idx >= state.core_globals.length() {
            raise InvalidCoreGlobalIndex(idx)
          } else {
            ComponentExtern::CoreGlobal(state.core_globals[idx])
          }
        0x04 =>
          if idx < 0 || idx >= state.core_tags.length() {
            raise InvalidCoreTagIndex(idx)
          } else {
            ComponentExtern::CoreTag(state.core_tags[idx])
          }
        0x05 | 0x10 =>
          if idx < 0 || idx >= state.core_types.length() {
            raise InvalidCoreTypeIndex(idx)
          } else {
            ComponentExtern::CoreType(state.core_types[idx])
          }
        0x11 =>
          if idx < 0 || idx >= state.core_modules.length() {
            raise InvalidCoreModuleIndex(idx)
          } else {
            ComponentExtern::CoreModule(state.core_modules[idx])
          }
        0x12 =>
          if idx < 0 || idx >= state.core_instances.length() {
            raise InvalidCoreInstanceIndex(idx)
          } else {
            ComponentExtern::CoreInstance(state.core_instances[idx])
          }
        _ => raise AliasTargetMismatch("unsupported core sort")
      }
  }
}

///|
fn resolve_sortidx_in_instance(
  sortidx : SortIdx,
  inst : ComponentInstance,
) -> ComponentExtern raise ComponentRuntimeError {
  let idx = sortidx.idx
  match sortidx.sort {
    Sort::Func =>
      if idx < 0 || idx >= inst.funcs.length() {
        raise InvalidFuncIndex(idx)
      } else {
        ComponentExtern::Func(inst.funcs[idx])
      }
    Sort::Value =>
      if idx < 0 || idx >= inst.values.length() {
        raise InvalidValueIndex(idx)
      } else {
        ComponentExtern::Value(inst.values[idx])
      }
    Sort::Type =>
      if idx < 0 || idx >= inst.types.length() {
        raise InvalidTypeIndex(idx)
      } else {
        ComponentExtern::Type(inst.types[idx])
      }
    Sort::Component =>
      if idx < 0 || idx >= inst.components.length() {
        raise InvalidComponentIndex(idx)
      } else {
        ComponentExtern::Component(inst.components[idx])
      }
    Sort::Instance =>
      if idx < 0 || idx >= inst.instances.length() {
        raise InvalidInstanceIndex(idx)
      } else {
        ComponentExtern::Instance(inst.instances[idx])
      }
    Sort::Core(core_sort) =>
      match core_sort {
        0x00 =>
          if idx < 0 || idx >= inst.core_funcs.length() {
            raise InvalidCoreFuncIndex(idx)
          } else {
            ComponentExtern::CoreFunc(inst.core_funcs[idx])
          }
        0x01 =>
          if idx < 0 || idx >= inst.core_tables.length() {
            raise InvalidCoreTableIndex(idx)
          } else {
            ComponentExtern::CoreTable(inst.core_tables[idx])
          }
        0x02 =>
          if idx < 0 || idx >= inst.core_mems.length() {
            raise InvalidCoreMemoryIndex(idx)
          } else {
            ComponentExtern::CoreMemory(inst.core_mems[idx])
          }
        0x03 =>
          if idx < 0 || idx >= inst.core_globals.length() {
            raise InvalidCoreGlobalIndex(idx)
          } else {
            ComponentExtern::CoreGlobal(inst.core_globals[idx])
          }
        0x04 =>
          if idx < 0 || idx >= inst.core_tags.length() {
            raise InvalidCoreTagIndex(idx)
          } else {
            ComponentExtern::CoreTag(inst.core_tags[idx])
          }
        0x05 | 0x10 =>
          if idx < 0 || idx >= inst.core_types.length() {
            raise InvalidCoreTypeIndex(idx)
          } else {
            ComponentExtern::CoreType(inst.core_types[idx])
          }
        0x11 =>
          if idx < 0 || idx >= inst.core_modules.length() {
            raise InvalidCoreModuleIndex(idx)
          } else {
            ComponentExtern::CoreModule(inst.core_modules[idx])
          }
        0x12 =>
          if idx < 0 || idx >= inst.core_instances.length() {
            raise InvalidCoreInstanceIndex(idx)
          } else {
            ComponentExtern::CoreInstance(inst.core_instances[idx])
          }
        _ => raise AliasTargetMismatch("unsupported core sort")
      }
  }
}

///|
fn append_alias(
  sort : Sort,
  ext : ComponentExtern,
  state : BuildState,
) -> Unit raise ComponentRuntimeError {
  match (sort, ext) {
    (Sort::Func, ComponentExtern::Func(f)) => state.funcs.push(f)
    (Sort::Value, ComponentExtern::Value(v)) => state.values.push(v)
    (Sort::Type, ComponentExtern::Type(t)) => state.types.push(t)
    (Sort::Component, ComponentExtern::Component(c)) => state.components.push(c)
    (Sort::Instance, ComponentExtern::Instance(i)) => state.instances.push(i)
    (Sort::Core(core_sort), ComponentExtern::CoreFunc(f)) =>
      if core_sort == 0x00 {
        state.core_funcs.push(f)
      } else {
        raise AliasTargetMismatch("core func")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreTable(t)) =>
      if core_sort == 0x01 {
        state.core_tables.push(t)
      } else {
        raise AliasTargetMismatch("core table")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreMemory(m)) =>
      if core_sort == 0x02 {
        state.core_mems.push(m)
      } else {
        raise AliasTargetMismatch("core memory")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreGlobal(g)) =>
      if core_sort == 0x03 {
        state.core_globals.push(g)
      } else {
        raise AliasTargetMismatch("core global")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreTag(t)) =>
      if core_sort == 0x04 {
        state.core_tags.push(t)
      } else {
        raise AliasTargetMismatch("core tag")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreType(t)) =>
      if core_sort == 0x05 || core_sort == 0x10 {
        state.core_types.push(t)
      } else {
        raise AliasTargetMismatch("core type")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreModule(m)) =>
      if core_sort == 0x11 {
        state.core_modules.push(m)
      } else {
        raise AliasTargetMismatch("core module")
      }
    (Sort::Core(core_sort), ComponentExtern::CoreInstance(i)) =>
      if core_sort == 0x12 {
        state.core_instances.push(i)
      } else {
        raise AliasTargetMismatch("core instance")
      }
    _ => raise AliasTargetMismatch("sort mismatch")
  }
}

///|
fn resolve_outer_alias(
  outer_stack : Array[ComponentInstance],
  depth : Int,
  sort : Sort,
  idx : Int,
) -> ComponentExtern raise ComponentRuntimeError {
  if depth < 0 || depth >= outer_stack.length() {
    raise OuterAliasOutOfRange(depth)
  }
  let outer = outer_stack[outer_stack.length() - 1 - depth]
  resolve_sortidx_in_instance({ sort, idx }, outer)
}

///|
fn extend_outer_stack(
  outer_stack : Array[ComponentInstance],
  env : ComponentInstance,
) -> Array[ComponentInstance] {
  let stack : Array[ComponentInstance] = []
  for s in outer_stack {
    stack.push(s)
  }
  stack.push(env)
  stack
}

///|
fn env_instance_from_state(
  name : String,
  state : BuildState,
  store : @runtime.Store,
) -> ComponentInstance {
  {
    name,
    types: state.types,
    funcs: state.funcs,
    values: state.values,
    components: state.components,
    instances: state.instances,
    resource_table: state.resource_table,
    stream_table: state.stream_table,
    async_state: state.async_state,
    core_modules: state.core_modules,
    core_instances: state.core_instances,
    core_funcs: state.core_funcs,
    core_types: state.core_types,
    core_tables: state.core_tables,
    core_mems: state.core_mems,
    core_globals: state.core_globals,
    core_tags: state.core_tags,
    exports: state.exports,
    store,
  }
}

///|
fn build_inline_core_instance(
  exports : Array[CoreInlineExport],
  state : BuildState,
) -> CoreInstance raise ComponentRuntimeError {
  let funcs : Map[String, CoreFuncRef] = {}
  let tables : Map[String, Int] = {}
  let memories : Map[String, Int] = {}
  let globals : Map[String, Int] = {}
  let tags : Map[String, Int] = {}
  for ex in exports {
    match resolve_sortidx(ex.sortidx, state) {
      ComponentExtern::CoreFunc(f) => funcs.set(ex.name, f)
      ComponentExtern::CoreTable(t) => tables.set(ex.name, t)
      ComponentExtern::CoreMemory(m) => memories.set(ex.name, m)
      ComponentExtern::CoreGlobal(g) => globals.set(ex.name, g)
      ComponentExtern::CoreTag(t) => tags.set(ex.name, t)
      _ => raise AliasTargetMismatch("inline core export")
    }
  }
  { funcs, tables, memories, globals, tags }
}

///|
fn split_core_import_name(name : String) -> (String, String) {
  let mut sep_idx = -1
  for i in 0..<name.length() {
    if i + 1 < name.length() &&
      name.code_unit_at(i) == ':' &&
      name.code_unit_at(i + 1) == ':' {
      sep_idx = i
    }
  }
  if sep_idx >= 0 {
    let mod_name = try! name[0:sep_idx].to_string()
    let field = try! name[sep_idx + 2:].to_string()
    (mod_name, field)
  } else {
    ("", name)
  }
}

///|
fn core_imports_from_args(
  args : Array[CoreInstantiateArg],
  state : BuildState,
) -> @runtime.Imports raise ComponentRuntimeError {
  let imports = @runtime.Imports::new()
  for arg in args {
    match resolve_sortidx(arg.sortidx, state) {
      ComponentExtern::CoreInstance(inst) => {
        // `with "mod" (instance ...)` supplies a whole namespace for core imports.
        let mod_name = arg.name
        for kv in inst.funcs.iter() {
          let (field, f) = kv
          imports.add_func(mod_name, field, f.instance.func_addrs[f.func_idx])
        }
        for kv in inst.tables.iter() {
          let (field, t) = kv
          imports.add_table(mod_name, field, t)
        }
        for kv in inst.memories.iter() {
          let (field, m) = kv
          imports.add_memory(mod_name, field, m)
        }
        for kv in inst.globals.iter() {
          let (field, g) = kv
          imports.add_global(mod_name, field, g)
        }
        for kv in inst.tags.iter() {
          let (field, t) = kv
          imports.add_tag(mod_name, field, t)
        }
      }
      ComponentExtern::CoreFunc(f) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_func(mod_name, field, f.instance.func_addrs[f.func_idx])
      }
      ComponentExtern::CoreTable(t) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_table(mod_name, field, t)
      }
      ComponentExtern::CoreMemory(m) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_memory(mod_name, field, m)
      }
      ComponentExtern::CoreGlobal(g) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_global(mod_name, field, g)
      }
      ComponentExtern::CoreTag(t) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_tag(mod_name, field, t)
      }
      _ => raise AliasTargetMismatch("core instantiate arg")
    }
  }
  imports
}

///|
