///|
fn resolve_sortidx(
  sortidx : SortIdx,
  state : BuildState,
) -> ComponentExtern raise ComponentRuntimeError {
  let idx = sortidx.idx
  match sortidx.sort {
    Func =>
      if idx < 0 || idx >= state.funcs.length() {
        raise InvalidFuncIndex(idx)
      } else {
        Func(state.funcs[idx])
      }
    Value =>
      if idx < 0 || idx >= state.values.length() {
        raise InvalidValueIndex(idx)
      } else {
        Value(state.values[idx])
      }
    Type =>
      if idx < 0 || idx >= state.types.length() {
        raise InvalidTypeIndex(idx)
      } else {
        Type(state.types[idx])
      }
    Component =>
      if idx < 0 || idx >= state.components.length() {
        raise InvalidComponentIndex(idx)
      } else {
        Component(state.components[idx])
      }
    Instance =>
      if idx < 0 || idx >= state.instances.length() {
        raise InvalidInstanceIndex(idx)
      } else {
        Instance(state.instances[idx])
      }
    Core(core_sort) =>
      match core_sort {
        0x00 =>
          if idx < 0 || idx >= state.core_funcs.length() {
            raise InvalidCoreFuncIndex(idx)
          } else {
            CoreFunc(state.core_funcs[idx])
          }
        0x01 =>
          if idx < 0 || idx >= state.core_tables.length() {
            raise InvalidCoreTableIndex(idx)
          } else {
            CoreTable(state.core_tables[idx])
          }
        0x02 =>
          if idx < 0 || idx >= state.core_mems.length() {
            raise InvalidCoreMemoryIndex(idx)
          } else {
            CoreMemory(state.core_mems[idx])
          }
        0x03 =>
          if idx < 0 || idx >= state.core_globals.length() {
            raise InvalidCoreGlobalIndex(idx)
          } else {
            CoreGlobal(state.core_globals[idx])
          }
        0x04 =>
          if idx < 0 || idx >= state.core_tags.length() {
            raise InvalidCoreTagIndex(idx)
          } else {
            CoreTag(state.core_tags[idx])
          }
        0x05 | 0x10 =>
          if idx < 0 || idx >= state.core_types.length() {
            raise InvalidCoreTypeIndex(idx)
          } else {
            CoreType(state.core_types[idx])
          }
        0x11 =>
          if idx < 0 || idx >= state.core_modules.length() {
            raise InvalidCoreModuleIndex(idx)
          } else {
            CoreModule(state.core_modules[idx])
          }
        0x12 =>
          if idx < 0 || idx >= state.core_instances.length() {
            raise InvalidCoreInstanceIndex(idx)
          } else {
            CoreInstance(state.core_instances[idx])
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
    Func =>
      if idx < 0 || idx >= inst.funcs.length() {
        raise InvalidFuncIndex(idx)
      } else {
        Func(inst.funcs[idx])
      }
    Value =>
      if idx < 0 || idx >= inst.values.length() {
        raise InvalidValueIndex(idx)
      } else {
        Value(inst.values[idx])
      }
    Type =>
      if idx < 0 || idx >= inst.types.length() {
        raise InvalidTypeIndex(idx)
      } else {
        Type(inst.types[idx])
      }
    Component =>
      if idx < 0 || idx >= inst.components.length() {
        raise InvalidComponentIndex(idx)
      } else {
        Component(inst.components[idx])
      }
    Instance =>
      if idx < 0 || idx >= inst.instances.length() {
        raise InvalidInstanceIndex(idx)
      } else {
        Instance(inst.instances[idx])
      }
    Core(core_sort) =>
      match core_sort {
        0x00 =>
          if idx < 0 || idx >= inst.core_funcs.length() {
            raise InvalidCoreFuncIndex(idx)
          } else {
            CoreFunc(inst.core_funcs[idx])
          }
        0x01 =>
          if idx < 0 || idx >= inst.core_tables.length() {
            raise InvalidCoreTableIndex(idx)
          } else {
            CoreTable(inst.core_tables[idx])
          }
        0x02 =>
          if idx < 0 || idx >= inst.core_mems.length() {
            raise InvalidCoreMemoryIndex(idx)
          } else {
            CoreMemory(inst.core_mems[idx])
          }
        0x03 =>
          if idx < 0 || idx >= inst.core_globals.length() {
            raise InvalidCoreGlobalIndex(idx)
          } else {
            CoreGlobal(inst.core_globals[idx])
          }
        0x04 =>
          if idx < 0 || idx >= inst.core_tags.length() {
            raise InvalidCoreTagIndex(idx)
          } else {
            CoreTag(inst.core_tags[idx])
          }
        0x05 | 0x10 =>
          if idx < 0 || idx >= inst.core_types.length() {
            raise InvalidCoreTypeIndex(idx)
          } else {
            CoreType(inst.core_types[idx])
          }
        0x11 =>
          if idx < 0 || idx >= inst.core_modules.length() {
            raise InvalidCoreModuleIndex(idx)
          } else {
            CoreModule(inst.core_modules[idx])
          }
        0x12 =>
          if idx < 0 || idx >= inst.core_instances.length() {
            raise InvalidCoreInstanceIndex(idx)
          } else {
            CoreInstance(inst.core_instances[idx])
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
    (Func, Func(f)) => state.funcs.push(f)
    (Value, Value(v)) => state.values.push(v)
    (Type, Type(t)) => state.types.push(t)
    (Component, Component(c)) => state.components.push(c)
    (Instance, Instance(i)) => state.instances.push(i)
    (Core(core_sort), CoreFunc(f)) =>
      if core_sort == 0x00 {
        state.core_funcs.push(f)
      } else {
        raise AliasTargetMismatch("core func")
      }
    (Core(core_sort), CoreTable(t)) =>
      if core_sort == 0x01 {
        state.core_tables.push(t)
      } else {
        raise AliasTargetMismatch("core table")
      }
    (Core(core_sort), CoreMemory(m)) =>
      if core_sort == 0x02 {
        state.core_mems.push(m)
      } else {
        raise AliasTargetMismatch("core memory")
      }
    (Core(core_sort), CoreGlobal(g)) =>
      if core_sort == 0x03 {
        state.core_globals.push(g)
      } else {
        raise AliasTargetMismatch("core global")
      }
    (Core(core_sort), CoreTag(t)) =>
      if core_sort == 0x04 {
        state.core_tags.push(t)
      } else {
        raise AliasTargetMismatch("core tag")
      }
    (Core(core_sort), CoreType(t)) =>
      if core_sort == 0x05 || core_sort == 0x10 {
        state.core_types.push(t)
      } else {
        raise AliasTargetMismatch("core type")
      }
    (Core(core_sort), CoreModule(m)) =>
      if core_sort == 0x11 {
        state.core_modules.push(m)
      } else {
        raise AliasTargetMismatch("core module")
      }
    (Core(core_sort), CoreInstance(i)) =>
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
  resolve_sortidx_in_instance({ sort, idx, }, outer)
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
  let funcs : Map[String, CoreFuncRef] = Map([])
  let tables : Map[String, Int] = Map([])
  let memories : Map[String, Int] = Map([])
  let globals : Map[String, Int] = Map([])
  let tags : Map[String, Int] = Map([])
  for ex in exports {
    match resolve_sortidx(ex.sortidx, state) {
      CoreFunc(f) => funcs.set(ex.name, f)
      CoreTable(t) => tables.set(ex.name, t)
      CoreMemory(m) => memories.set(ex.name, m)
      CoreGlobal(g) => globals.set(ex.name, g)
      CoreTag(t) => tags.set(ex.name, t)
      _ => raise AliasTargetMismatch("inline core export")
    }
  }
  { funcs, tables, memories, globals, tags, }
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
    let mod_name = name[0:sep_idx].to_owned()
    let field = name[sep_idx + 2:].to_owned()
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
  let imports = @runtime.Imports::Imports()
  for arg in args {
    match resolve_sortidx(arg.sortidx, state) {
      CoreInstance(inst) => {
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
      CoreFunc(f) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_func(mod_name, field, f.instance.func_addrs[f.func_idx])
      }
      CoreTable(t) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_table(mod_name, field, t)
      }
      CoreMemory(m) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_memory(mod_name, field, m)
      }
      CoreGlobal(g) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_global(mod_name, field, g)
      }
      CoreTag(t) => {
        let (mod_name, field) = split_core_import_name(arg.name)
        imports.add_tag(mod_name, field, t)
      }
      _ => raise AliasTargetMismatch("core instantiate arg")
    }
  }
  imports
}

///|
fn core_args_may_suspend(
  args : Array[CoreInstantiateArg],
  state : BuildState,
) -> Bool raise ComponentRuntimeError {
  for arg in args {
    match resolve_sortidx(arg.sortidx, state) {
      CoreInstance(instance) =>
        for entry in instance.funcs.iter() {
          let (_, func) = entry
          if func.may_suspend {
            return true
          }
        }
      CoreFunc(func) => if func.may_suspend { return true }
      CoreTable(_) | CoreMemory(_) | CoreGlobal(_) | CoreTag(_) => ()
      _ => raise AliasTargetMismatch("core instantiate arg")
    }
  }
  false
}

///|
fn core_args_native_eligible(
  args : Array[CoreInstantiateArg],
  state : BuildState,
) -> Bool raise ComponentRuntimeError {
  for arg in args {
    match resolve_sortidx(arg.sortidx, state) {
      CoreInstance(instance) =>
        for entry in instance.funcs.iter() {
          let (_, func) = entry
          if !func.native_eligible {
            return false
          }
        }
      CoreFunc(func) => if !func.native_eligible { return false }
      // An imported function table can indirect through a component adapter.
      // Keep such modules interpreted until nested native entry is supported.
      CoreTable(_) => return false
      CoreMemory(_) | CoreGlobal(_) | CoreTag(_) => ()
      _ => raise AliasTargetMismatch("core instantiate arg")
    }
  }
  true
}

///|
fn supplied_core_func_for_import(
  mod_name : String,
  field : String,
  args : Array[CoreInstantiateArg],
  state : BuildState,
) -> CoreFuncRef? raise ComponentRuntimeError {
  for arg in args {
    match resolve_sortidx(arg.sortidx, state) {
      CoreInstance(inst) =>
        if arg.name == mod_name {
          match inst.funcs.get(field) {
            Some(f) => return Some(f)
            None => ()
          }
        }
      CoreFunc(f) => {
        let (arg_mod, arg_field) = split_core_import_name(arg.name)
        if arg_mod == mod_name && arg_field == field {
          return Some(f)
        }
      }
      _ => ()
    }
  }
  None
}

///|
fn validate_core_import_args(
  module_ : @types.Module,
  args : Array[CoreInstantiateArg],
  state : BuildState,
) -> Unit raise ComponentRuntimeError {
  for imp in module_.imports {
    match imp.desc {
      Func(tyidx) => {
        let expected = module_.validated_func_type_at(tyidx)
        match
          supplied_core_func_for_import(imp.mod_name, imp.name, args, state) {
          Some(f) => {
            let actual = core_func_ref_type(f)
            if actual != expected {
              raise ImportTypeMismatch(
                "type mismatch for export `\{imp.name}` of module instantiation argument `\{imp.mod_name}`: expected \{expected}, found \{actual}",
              )
            }
          }
          None => ()
        }
      }
      _ => ()
    }
  }
}

///|
