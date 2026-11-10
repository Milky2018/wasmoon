///|
fn resolve_sortidx(
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
    (Func, Func(f)) => state.instance.funcs.push(f)
    (Value, Value(v)) => state.instance.values.push(v)
    (Type, Type(t)) => state.append_declared_type(t)
    (Component, Component(c)) => state.instance.components.push(c)
    (Instance, Instance(i)) => state.instance.instances.push(i)
    (Core(core_sort), CoreFunc(f)) =>
      if core_sort == 0x00 {
        state.instance.core_funcs.push(f)
      } else {
        raise AliasTargetMismatch("core func")
      }
    (Core(core_sort), CoreTable(t)) =>
      if core_sort == 0x01 {
        state.instance.core_tables.push(t)
      } else {
        raise AliasTargetMismatch("core table")
      }
    (Core(core_sort), CoreMemory(m)) =>
      if core_sort == 0x02 {
        state.instance.core_mems.push(m)
      } else {
        raise AliasTargetMismatch("core memory")
      }
    (Core(core_sort), CoreGlobal(g)) =>
      if core_sort == 0x03 {
        state.instance.core_globals.push(g)
      } else {
        raise AliasTargetMismatch("core global")
      }
    (Core(core_sort), CoreTag(t)) =>
      if core_sort == 0x04 {
        state.instance.core_tags.push(t)
      } else {
        raise AliasTargetMismatch("core tag")
      }
    (Core(core_sort), CoreType(t)) =>
      if core_sort == 0x05 || core_sort == 0x10 {
        state.instance.core_types.push(t)
      } else {
        raise AliasTargetMismatch("core type")
      }
    (Core(core_sort), CoreModule(m)) =>
      if core_sort == 0x11 {
        state.instance.core_modules.push(m)
      } else {
        raise AliasTargetMismatch("core module")
      }
    (Core(core_sort), CoreInstance(i)) =>
      if core_sort == 0x12 {
        state.instance.core_instances.push(i)
      } else {
        raise AliasTargetMismatch("core instance")
      }
    _ => raise AliasTargetMismatch("sort mismatch")
  }
}

///|
fn resolve_outer_alias(
  outer_stack : Array[ComponentInstance],
  depth : Int32,
  sort : Sort,
  idx : Int32,
) -> ComponentExtern raise ComponentRuntimeError {
  if depth < 0 || depth >= outer_stack.length() {
    raise OuterAliasOutOfRange(depth)
  }
  let outer = outer_stack[outer_stack.length() - 1 - depth]
  resolve_sortidx({ sort, idx, }, outer)
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
fn ComponentInstance::environment(
  self : ComponentInstance,
) -> ComponentInstance {
  { ..self, name: "\{self.name}::env", }
}

///|
fn build_inline_core_instance(
  exports : Array[CoreInlineExport],
  state : ComponentInstance,
) -> CoreInstance raise ComponentRuntimeError {
  let funcs : Map[String, CoreFuncRef] = Map([])
  let tables : Map[String, Int32] = Map([])
  let memories : Map[String, Int32] = Map([])
  let globals : Map[String, Int32] = Map([])
  let tags : Map[String, Int32] = Map([])
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
  state : ComponentInstance,
  store : @runtime.Store,
) -> @runtime.Imports raise ComponentRuntimeError {
  let imports = @runtime.Imports::Imports(store)
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
  state : ComponentInstance,
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
  state : ComponentInstance,
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
  state : ComponentInstance,
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
  state : ComponentInstance,
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
