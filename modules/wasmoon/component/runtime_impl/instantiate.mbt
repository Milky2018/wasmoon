///|
/// Per-component state shared by all section handlers during instantiation.
priv struct ComponentInstantiationFrame {
  linker : ComponentLinker
  name : String
  component : Component
  overrides : Map[String, ComponentExtern]
  outer_stack : Array[ComponentInstance]
  state : BuildState
  entry_state : ComponentInstanceEntryState
  store : @runtime.Store
  async_state : AsyncState
  staged : Array[(String, ComponentInstance)]
}

///|
fn instantiate_component(
  linker : ComponentLinker,
  name : String,
  component : Component,
  overrides : Map[String, ComponentExtern],
  outer_stack : Array[ComponentInstance],
  staged : Array[(String, ComponentInstance)],
) -> ComponentInstance raise ComponentRuntimeError {
  let stream_table = if outer_stack.length() > 0 {
    outer_stack[outer_stack.length() - 1].stream_table
  } else {
    match linker.host_runtime.val {
      Some(runtime) => runtime.stream_table
      None => StreamTable()
    }
  }
  let async_state = if outer_stack.length() > 0 {
    outer_stack[outer_stack.length() - 1].async_state
  } else {
    match linker.host_runtime.val {
      Some(runtime) => runtime.async_state
      None => AsyncState(stream_table, core_engine=linker.core_engine())
    }
  }
  let state = BuildState::BuildState(stream_table, async_state)
  if outer_stack.length() > 0 {
    let parent_table = outer_stack[outer_stack.length() - 1].resource_table
    let ancestors : Array[Int] = []
    for ancestor in parent_table.ancestors.val {
      ancestors.push(ancestor)
    }
    ancestors.push(parent_table.id)
    state.resource_table.ancestors.val = ancestors
  }
  state.async_state.resource_tables.set(
    state.resource_table.id,
    state.resource_table,
  )
  let entry_state = ComponentInstanceEntryState::new()
  let store = linker.get_store()
  let frame : ComponentInstantiationFrame = {
    linker,
    name,
    component,
    overrides,
    outer_stack,
    state,
    entry_state,
    store,
    async_state,
    staged,
  }
  run_component_sections(frame) catch {
    error => {
      state.release_aborted()
      raise error
    }
  }
  entry_state.enable()
  let instance = env_instance_from_state(name, state, store)
  // Registration is transactional: the frame stages its instance, nested
  // frames included, and only the root commits the whole tree into the
  // linker once it succeeds on a still-open linker. Rollback releases every
  // staged graph, so a failed root leaves nothing observable behind.
  staged.push((name, instance))
  instance
}

///|
fn run_component_sections(
  frame : ComponentInstantiationFrame,
) -> Unit raise ComponentRuntimeError {
  let {
    linker,
    name,
    component,
    overrides,
    outer_stack,
    state,
    entry_state,
    store,
    async_state,
    staged,
  } = frame
  for section in component.binary.sections {
    match section.id {
      1 => {
        if @component.sniff_binary_kind(section.payload) != Some(CoreModule) {
          raise CoreModuleParseError("unknown binary version")
        }
        let core_module = @parser.parse_module(section.payload) catch {
          e => raise CoreModuleParseError(e.to_string())
        }
        state.core_modules.push(core_module)
      }
      2 => {
        let core_instances = parse_core_instance_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for inst in core_instances {
          match inst.expr {
            Instantiate(module_idx, args) => {
              if module_idx < 0 || module_idx >= state.core_modules.length() {
                raise InvalidCoreModuleIndex(module_idx)
              }
              let mod_ = state.core_modules[module_idx]
              validate_core_import_args(mod_, args, state)
              let imports = core_imports_from_args(args, state)
              let may_suspend = core_args_may_suspend(args, state)
              let native_eligible = core_args_native_eligible(args, state)
              let module_name = "\{name}::coreinst\{state.core_instances.length()}"
              clear_canon_trap_message()
              // Core module instantiation can execute start functions that call
              // canonical host imports. Give start its own task-scoped borrow,
              // cancellation, and continuation state.
              let inst_task_id = alloc_task_id(async_state)
              // Core start runs during instantiation and must not block.
              push_task(async_state, inst_task_id, false)
              let instance = @executor.instantiate_module_with_imports(
                store, mod_, imports,
              ) catch {
                e => {
                  pop_task(async_state)
                  drop_task_thread(async_state, inst_task_id)
                  match canon_trap_message[0] {
                    Some(msg) => raise CoreModuleInstantiateError(msg)
                    None => raise CoreModuleInstantiateError(e.to_string())
                  }
                }
              }
              pop_task(async_state)
              drop_task_thread(async_state, inst_task_id)
              linker.core_linker.register(module_name, instance) catch {
                error => raise CoreModuleInstantiateError(error.to_string())
              }
              linker.core_engine().register_instance(store, mod_, instance)
              state.core_instances.push(
                core_instance_from_module(
                  instance,
                  linker.core_engine(),
                  module_name,
                  may_suspend,
                  native_eligible,
                ),
              )
            }
            InlineExports(exports) =>
              state.core_instances.push(
                build_inline_core_instance(exports, state),
              )
          }
        }
      }
      3 => {
        // Core type section payload is a vec of core typedefs; store each
        // typedef's raw bytes so core:typeidx references work correctly.
        let reader = Reader::Reader(section.payload)
        let n = reader.read_leb_u32() catch {
          e => raise ComponentParseError(e.to_string())
        }
        for _i in 0..<n {
          let start = reader.pos
          skip_core_typedef(reader) catch {
            e => raise ComponentParseError(e.to_string())
          }
          let end = reader.pos
          state.core_types.push(bytes_sub(section.payload, start, end))
        }
        if !reader.is_eof() {
          raise ComponentParseError("invalid core type section")
        }
      }
      4 => {
        let nested = parse_component(section.payload) catch {
          e => raise ComponentParseError(e.to_string())
        }
        let env = env_instance_from_state("\{name}::env", state, store)
        state.components.push({
          component: nested,
          outer_stack: extend_outer_stack(outer_stack, env),
        })
      }
      5 => {
        let instances = parse_instance_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for inst in instances {
          match inst.expr {
            Instantiate(component_idx, args) => {
              if component_idx < 0 || component_idx >= state.components.length() {
                raise InvalidComponentIndex(component_idx)
              }
              let closure = state.components[component_idx]
              let overrides_for_child : Map[String, ComponentExtern] = Map([])
              for arg in args {
                let ext = resolve_sortidx(arg.sortidx, state)
                overrides_for_child.set(arg.name, ext)
              }
              let nested = instantiate_component(
                linker,
                "\{name}::component\{component_idx}",
                closure.component,
                overrides_for_child,
                closure.outer_stack,
                staged,
              )
              state.instances.push(nested)
            }
            InlineExports(exports) => {
              let export_map : Map[String, ComponentExtern] = Map([])
              for ex in exports {
                let ext = resolve_sortidx(ex.sortidx, state)
                export_map.set(ex.name, ext)
              }
              let inline_inst : ComponentInstance = {
                name: "\{name}::inline\{state.instances.length()}",
                types: state.types,
                funcs: state.funcs,
                values: state.values,
                components: state.components,
                instances: [],
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
                exports: export_map,
                store,
              }
              state.instances.push(inline_inst)
            }
          }
        }
      }
      6 => {
        let aliases = parse_alias_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for alias_decl in aliases {
          let ext = match alias_decl.target {
            Export(instance_idx, name) => {
              if instance_idx < 0 || instance_idx >= state.instances.length() {
                raise InvalidInstanceIndex(instance_idx)
              }
              match state.instances[instance_idx].exports.get(name) {
                Some(v) => v
                None => raise UnknownExport(name)
              }
            }
            CoreExport(core_inst_idx, name) => {
              if core_inst_idx < 0 ||
                core_inst_idx >= state.core_instances.length() {
                raise InvalidCoreInstanceIndex(core_inst_idx)
              }
              let core_inst = state.core_instances[core_inst_idx]
              match alias_decl.sort {
                Core(0x00) =>
                  match core_inst.funcs.get(name) {
                    Some(v) => CoreFunc(v)
                    None => raise UnknownExport(name)
                  }
                Core(0x01) =>
                  match core_inst.tables.get(name) {
                    Some(v) => CoreTable(v)
                    None => raise UnknownExport(name)
                  }
                Core(0x02) =>
                  match core_inst.memories.get(name) {
                    Some(v) => CoreMemory(v)
                    None => raise UnknownExport(name)
                  }
                Core(0x03) =>
                  match core_inst.globals.get(name) {
                    Some(v) => CoreGlobal(v)
                    None => raise UnknownExport(name)
                  }
                Core(0x04) =>
                  match core_inst.tags.get(name) {
                    Some(v) => CoreTag(v)
                    None => raise UnknownExport(name)
                  }
                _ => raise AliasTargetMismatch("core export sort")
              }
            }
            Outer(ct, idx) =>
              resolve_outer_alias(
                extend_outer_stack(
                  outer_stack,
                  env_instance_from_state("\{name}::env", state, store),
                ),
                ct,
                alias_decl.sort,
                idx,
              )
          }
          append_alias(alias_decl.sort, ext, state)
        }
      }
      7 => {
        let types = parse_type_section(section.payload) catch {
          e => raise ComponentParseError(e.to_string())
        }
        for t in types {
          let t2 = match t {
            ResourceType(id, rep, dtor, kind) =>
              if id < 0 {
                TypeDef::ResourceType(
                  linker.alloc_resource_id(),
                  rep,
                  dtor,
                  kind,
                )
              } else {
                t
              }
            _ => t
          }
          state.types.push(Some(t2))
        }
      }
      8 => process_canon_section(section.payload, state, store, entry_state)
      9 => {
        let start = parse_start_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        if start.func_idx < 0 || start.func_idx >= state.funcs.length() {
          raise InvalidFuncIndex(start.func_idx)
        }
        let args : Array[ComponentValue] = []
        for idx in start.args {
          if idx < 0 || idx >= state.values.length() {
            raise InvalidValueIndex(idx)
          }
          args.push(state.values[idx])
        }
        let results = call_component_func(
          state.funcs[start.func_idx],
          args,
          store,
          state.resource_table,
          state.async_state,
        )
        if results.length() != start.results {
          raise InvalidStartResultCount(results.length())
        }
        for r in results {
          state.values.push(r)
        }
      }
      10 => {
        let imports = parse_import_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        let import_outer_stack = extend_outer_stack(
          outer_stack,
          env_instance_from_state("\{name}::env", state, store),
        )
        for imp in imports {
          let ext = resolve_import(
            linker,
            overrides,
            import_outer_stack,
            imp.name,
            imp.desc,
            state.types,
            state.core_types,
            store,
          )
          match imp.desc {
            CoreModuleType(_) =>
              match ext {
                CoreModule(m) => state.core_modules.push(m)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            FuncType(_) =>
              match ext {
                Func(f) => state.funcs.push(f)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            Value(_) =>
              match ext {
                Value(v) => state.values.push(v)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            Type(_) =>
              match ext {
                Type(t) => state.types.push(t)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            ComponentType(_) =>
              match ext {
                Component(c) => state.components.push(c)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
            InstanceType(_) =>
              match ext {
                Instance(i) => state.instances.push(i)
                _ => raise UnknownImport(decode_import_name(imp.name))
              }
          }
        }
      }
      11 => {
        let exports = parse_export_section(section.payload) catch {
          e => raise CoreModuleInstantiateError(e.to_string())
        }
        for exp in exports {
          let name = decode_export_name(exp.name)
          let ext = resolve_sortidx(exp.sortidx, state)
          state.exports.set(name, ext)
          append_alias(exp.sortidx.sort, ext, state)
        }
      }
      _ => ()
    }
  }
}
